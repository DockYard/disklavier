defmodule DisklavierWeb.HomeLive do
  use DisklavierWeb, :live_view
  use DisklavierNative, :live_view

  def mount(_, _, socket) do
    categories = fetch_categories()

    {name, category_id} = Enum.find(categories, fn({name, _category_id}) -> name == "All" end)

    songs = filter_songs_by_category(category_id)

    {:ok, assign(socket, %{categories: categories, songs: songs, category_id: category_id, category_name: name})}
  end

  def handle_event("category_choice", %{"selection" => selected_id}, socket) do
    songs = filter_songs_by_category(selected_id)
    {name, category_id} = Enum.find(socket.assigns.categories, fn({_name, category_id}) -> category_id == selected_id end)
    {:noreply, assign(socket, %{category_id: category_id, category_name: name, songs: songs})}
  end

  defp fetch_categories() do
    [{"category_data", categories}] = :ets.lookup(:disklavier_data, "category_data")

    Enum.map(categories, fn({id, name}) -> {name, id} end)
  end

  defp filter_songs_by_category(category_id) do
    [{"song_data", songs}] = :ets.lookup(:disklavier_data, "song_data")
    songs = Enum.map(songs, fn({id, song}) ->
      Map.put(song, "id", id)
    end)
    Enum.filter(songs, fn(%{"categories" => categories}) -> Enum.member?(categories, category_id) end)
  end
end
