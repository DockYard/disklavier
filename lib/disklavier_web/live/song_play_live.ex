defmodule DisklavierWeb.SongPlayLive do
  use DisklavierWeb, :live_view
  use DisklavierNative, :live_view

  def mount(params, _session, socket) do
    [{"song_data", songs}] = :ets.lookup(:disklavier_data, "song_data")
    songs = Enum.map(songs, fn({id, song}) ->
      Map.put(song, "id", id)
    end)

    song = Enum.find(songs, fn(song) -> song["id"] == params["id"] end)

    {:ok, assign(socket, :song, song)}
  end
end
