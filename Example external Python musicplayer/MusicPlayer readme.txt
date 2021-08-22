If you want to make your own music player you can probably just check the source for mine and figure it out yourself but basically:

- Mod will write "start" to music_state.txt when it wants music to start playing
- Mod will write "stop" (or stop_force... something containing stop) when it wants it to stop

So your musicplayer just needs to check the music_state.txt file every second or so to see what it wants. 