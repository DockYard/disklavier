defmodule DisklavierWeb.SongLive do
  use DisklavierWeb, :live_view
  use DisklavierNative, :live_view

  def mount(params, _session, socket) do
    [{"song_data", songs}] = :ets.lookup(:disklavier_data, "song_data")
    songs = Enum.map(songs, fn({id, song}) ->
      Map.put(song, "id", id)
    end)

    song = Enum.find(songs, fn(song) -> song["id"] == params["id"] end)

    {:ok, assign(socket, %{song: song, show: false})}
  end

  def handle_event("show_modal", _, socket) do
    {:noreply, assign(socket, show: true)}
  end

  def handle_event("dismiss_modal", _, socket) do
    {:noreply, assign(socket, show: false)}
  end
end
