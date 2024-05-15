# Disklavier

When starting this app it will take a minute or two to scrape
all of the data from Disklavier's website. This repo doesn't
use a database, only puts the data into ETS so every time you bounce
the server it will block on getting that data.

## Get started

```bash
> mix deps.get
> mix phx.server
```

Open the Xcode project:

```terminal
> open native/swiftui/Disklavier.xcodeproj
```

Make sure that the non-watch target and TvOS simulator are chosen:

You may need to "Trust & Enable" a few times.

Compile and run.
