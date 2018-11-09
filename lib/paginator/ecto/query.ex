defmodule Paginator.Ecto.Query do
  @moduledoc false

  import Ecto.Query

  alias Paginator.Config

  def paginate(queryable, config \\ [])

  def paginate(queryable, %Config{} = config) do
    queryable
    |> maybe_where(config)
    |> limit(^query_limit(config))
  end

  def paginate(queryable, opts) do
    config = Config.new(opts)
    paginate(queryable, config)
  end

  defp get_operator(:asc, :before), do: :lt
  defp get_operator(:desc, :before), do: :gt
  defp get_operator(:asc, :after), do: :gt
  defp get_operator(:desc, :after), do: :lt

  defp get_operator_for_field(cursor_fields, key, direction) do
    Keyword.get(cursor_fields, key)
    |> get_operator(direction)
  end

  defp filter_values(query, fields, values, cursor_direction) do
    sorts =
      Keyword.keys(fields)
      |> Enum.zip(values)
      |> Enum.reject(fn val -> match?({_column, nil}, val) end)

    dynamic_sorts =
      sorts
      |> Enum.with_index()
      |> Enum.reduce(true, fn {{column, value}, i}, dynamic_sorts ->
        dynamic = true

        dynamic =
          case get_operator_for_field(fields, column, cursor_direction) do
            :lt ->
              dynamic([q], field(q, ^column) < ^value and ^dynamic)

            :gt ->
              dynamic([q], field(q, ^column) > ^value and ^dynamic)
          end

        dynamic =
          sorts
          |> Enum.take(i)
          |> Enum.reduce(dynamic, fn {prev_column, prev_value}, dynamic ->
            dynamic([q], field(q, ^prev_column) == ^prev_value and ^dynamic)
          end)

        if i == 0 do
          dynamic([q], ^dynamic and ^dynamic_sorts)
        else
          dynamic([q], ^dynamic or ^dynamic_sorts)
        end
      end)

    where(query, [q], ^dynamic_sorts)
  end

  defp maybe_where(query, %Config{
         after: nil,
         before: nil,
         cursor_fields: cursor_fields
       }) do
    validate_cursor_fields!(cursor_fields)

    query
  end

  defp maybe_where(query, %Config{
         after_values: after_values,
         before: nil,
         cursor_fields: cursor_fields
       }) do
    validate_cursor_fields!(cursor_fields)

    query
    |> filter_values(cursor_fields, after_values, :after)
  end

  defp maybe_where(query, %Config{
         after: nil,
         before_values: before_values,
         cursor_fields: cursor_fields
       }) do
    validate_cursor_fields!(cursor_fields)

    query
    |> filter_values(cursor_fields, before_values, :before)
    |> reverse_order_bys()
  end

  defp maybe_where(query, %Config{
         after_values: after_values,
         before_values: before_values,
         cursor_fields: cursor_fields
       }) do
    validate_cursor_fields!(cursor_fields)

    query
    |> filter_values(cursor_fields, after_values, :after)
    |> filter_values(cursor_fields, before_values, :before)
  end

  defp validate_cursor_fields!(cursor_fields) do
    # the list must be a keyword list
    unless Keyword.keyword?(cursor_fields),
      do: raise("Expected cursor_fields to be a keyword list.")

    Enum.each(cursor_fields, fn {key, value} ->
      unless value == :desc or value == :asc do
        raise(
          "Value for field :#{key} in cursor_fields is invalid, please use either :desc or :asc"
        )
      end
    end)
  end

  #  In order to return the correct pagination cursors, we need to fetch one more
  # # record than we actually want to return.
  defp query_limit(%Config{limit: limit}) do
    limit + 1
  end

  # This code was taken from https://github.com/elixir-ecto/ecto/blob/v2.1.4/lib/ecto/query.ex#L1212-L1226
  defp reverse_order_bys(query) do
    update_in(query.order_bys, fn
      [] ->
        []

      order_bys ->
        for %{expr: expr} = order_by <- order_bys do
          %{
            order_by
            | expr:
                Enum.map(expr, fn
                  {:desc, ast} -> {:asc, ast}
                  {:asc, ast} -> {:desc, ast}
                end)
          }
        end
    end)
  end
end
