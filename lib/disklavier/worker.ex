defmodule Disklavier.Worker do
  use GenServer
  require Logger

  @day 1000 * 60 * 60 * 24

  defstruct [:conn, requests: %{}]

  def start_link([]) do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    :ets.new(:disklavier_data, [:named_table])
    update_data()
    Logger.info("Disklavier data scraped!")
    {:ok, nil}
  end

  def handle_info(:update_data, state) do
    update_data()
    {:noreply, state}
  end

  defp update_data() do
    update_category_data()
    |> update_song_data()

    update_schedule_data()
    Process.send_after(self(), :update_data, @day)
  end

  defp update_category_data do
    {:ok, response} = HTTPoison.get("https://www.yamaha.com/usa/disklaviertv/ondemand.html")

    category_data =
      Floki.parse_document!(response.body)
      |> Floki.find("table#ctl00_RemoteLiveContentPlaceHolder_dtCategoryList td")
      |> Enum.into(%{}, fn(category_cell) ->
        uri =
          category_cell
          |> find_first_element("a")
          |> attribute("href")
          |> URI.parse()

        category_id =
          uri.query
          |> URI.decode_query()
          |> Map.get("CATID")

        {category_id, get_text(category_cell)}
      end)

    :ets.insert(:disklavier_data, {"category_data", category_data})

    category_data
  end

  defp update_song_data(category_data) do
    category_url = "https://www.yamaha.com/usa/disklaviertv/result.html"

    song_data =
      Enum.reduce(category_data, %{}, fn({category_id, _name}, song_data) ->
        {:ok, response} = HTTPoison.get("#{category_url}?CATID=#{category_id}")
        Floki.parse_document!(response.body)
        |> Floki.find("tr.play-list-item")
        |> Enum.reduce(song_data, fn(row, song_data) ->
          song_id = attribute(row, "cntid")

          song = case Map.fetch(song_data, song_id) do
            {:ok, %{"categories" => category_ids} = song} ->
              Map.put(song, "categories", [category_id | category_ids])
            :error ->
              %{
                "artist" => Floki.find(row, "td") |> Enum.at(1) |> get_text(),
                "title" => Floki.find(row, "td") |> Enum.at(2) |> get_text() |> String.replace(~r/[\s|\n|\r]+/, " "),
                "video_url" => hd_or_sd_video_url(attribute(row, "hdm4v"), attribute(row, "m4v")),
                "poster_url" => attribute(row, "poster") |> prepend_protocol(),
                "description" => attribute(row, "desc"),
                "categories" => [category_id],
                "uploaded_at" => attribute(row, "uplddt") |> to_datetime()
              }
          end

          Map.put(song_data, song_id, song)
        end)
      end)

    :ets.insert(:disklavier_data, {"song_data", song_data})
  end

  defp update_schedule_data do
    {:ok, response} = HTTPoison.get("http://www.yamaha.com/usa/disklaviertv/eventlist.html")

    schedule_data =
      response.body
      |> Floki.parse_document!()
      |> Floki.find("div.series >*")
      |> Enum.reverse()
      |> Enum.reduce([%{}], fn(elem, [head | tail] = elems) ->
        case [Floki.attribute(elem, "class"), Floki.attribute(elem, "id"), Floki.attribute(elem, "style")] do
          [["hr"], _id, _style] ->
            [[] | elems]
          [_class, id, style] when id == ["legends"] or style == ["clear: both;"] ->
            elems
          _ ->
            [[elem | head] | tail]
        end
      end)
      |> List.delete_at(-1)
      |> Enum.into(%{}, fn(event) ->
        {
          Floki.find(event, "input[type='hidden']") |> Floki.attribute("value") |> Enum.at(0),
          %{
            "poster_url" => parse_event_poster_url(event),
            "artist" => parse_event_artist(event),
            "title_1" => parse_event_title_1(event),
            "title_2" => parse_event_title_2(event),
            "red" => parse_event_red(event),
            "description" => parse_event_description(event),
            "datetime_range" => parse_event_datetime_range(event)
          }
        }
      end)

    :ets.insert(:disklavier_data, {"schedule_data", schedule_data})
  end

  defp parse_event_poster_url(event) do
    event
    |> Floki.find("img:not([alt='print']):not(.live):not(.ondemand)")
    |> Enum.at(0)
    |> Floki.attribute("src")
    |> Enum.at(0)
    |> prepend_host()
  end

  defp parse_event_artist(event) do
    event
    |> Floki.find("h2")
    |> Floki.text(deep: false)
    |> String.trim()
  end

  defp parse_event_title_1(event) do
    event
    |> Floki.find("h2 i")
    |> Floki.text()
    |> String.trim()
  end

  defp parse_event_title_2(event) do
    event
    |> Floki.find("h2 b")
    |> Floki.text()
    |> String.trim()
  end

  defp parse_event_red(event) do
    event
    |> Floki.find("h2 span[style='color:red']")
    |> Floki.text()
    |> String.trim()
  end

  defp parse_event_description(event) do
    event
    |> Floki.find("p >*")
    |> Floki.raw_html()
  end

  defp parse_event_datetime_range(event) do
    datetime_regex = ~r/sdate.+"(.+)".+\s+edate.+"(.+)".+\s+sdateTime.+"(.+)".+\s+edateTime.+"(.+)".+\s+var\stimeZone.+"(.+)".+\s+var\sendtimeZone.+"(.+)"/

    script =
      event
      |> Floki.find(".dates a script")
      |> Floki.text(js: true)

    [_, start_date, end_date, start_time, end_time, start_timezone, end_timezone] = Regex.run(datetime_regex, script)

    {:ok, start_datetime} = convert_datetime(start_date, start_time, start_timezone)
    {:ok, end_datetime} = convert_datetime(end_date, end_time, end_timezone)

    {start_datetime, end_datetime}
  end

  defp convert_datetime(date, time, timezone \\ "PDT") do
    [month, day, year] =
      date
      |> String.split("/")
      |> Enum.map(&String.to_integer/1)

    [_, hour, minute] = Regex.run(~r/(\d+):(\d+)/, time)

    hour = String.to_integer(hour)
    minute = String.to_integer(minute)

    timezone = normalize_timezone(timezone)

    {:ok, naive_datetime} = NaiveDateTime.from_erl({{year, month, day}, {hour, minute, 0}})
    DateTime.from_naive(naive_datetime, timezone)
  end

  defp normalize_timezone(timezone) do
    case timezone do
      "PDT" -> "America/Los_Angeles"
      "EDT" -> "America/New_York"
      _ -> "America/Los_Angeles"
    end
  end

  defp hd_or_sd_video_url(encoded_hdm4v, encoded_m4v) do
    with {:ok, hdm4v_url} <- decode_url(encoded_hdm4v),
         {:ok, %HTTPoison.Response{status_code: 200}} <- HTTPoison.head(hdm4v_url) do
           hdm4v_url
         else
           _error ->
             {:ok, m4v_url} = decode_url(encoded_m4v)
             m4v_url
         end
  end

  defp decode_url(""), do: {:error, ""}
  defp decode_url(encoded_url) do
    splitter = "1213"
    char_code_offset = 51

    url =
      String.split(encoded_url, splitter)
      |> Enum.map(fn(char_code) ->
        String.to_integer(char_code) + char_code_offset
      end)
      |> prepend_protocol()

    {:ok, url}
  end

  defp prepend_protocol(uri),
    do: "https://#{uri}"

  defp prepend_host(path),
    do: prepend_protocol("www.yamaha.com#{path}")

  defp attribute(element, attribute_name),
    do: Floki.attribute(element, attribute_name) |> Enum.at(0) |> String.trim()

  defp find_first_element(trunk_element, pattern),
    do: Floki.find(trunk_element, pattern) |> Enum.at(0)

  defp get_text(element),
    do: Floki.text(element) |> String.trim()

  defp to_datetime(datetime) do
    [_, date, time] = Regex.run(~r/(\d+\/\d+\/\d+) (\d+:\d+:\d+\s\w+)/, datetime)
    {:ok, datetime} = convert_datetime(date, time)
    datetime
  end
end
