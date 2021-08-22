import os, time, random, sys
from pygame import mixer

filepath = "F:/Games/SteamLibrary/steamapps/common/Cyberpunk 2077/bin/x64/plugins/cyber_engine_tweaks/mods/VsProCyberpsycho/music_state.txt"
song_folder = "./songs/"
song_exts = [".mp3", ".wav", ".flac", ".m4a"]
sleep_time = 1
volume = 0.7
change_song_after = 60

playing_music = False

def clear():
	with open(filepath,"w") as f:
		f.write("-")

songs = []
for f in os.listdir(song_folder):
	fullpath = os.path.join(song_folder, f)
	if os.path.isfile(fullpath) and os.path.splitext(f)[1].lower() in song_exts:
		songs.append(fullpath)

print("found songs:")
for s in songs:
	print(s)


mixer.init()
mixer.Channel(0).set_volume(volume)
print("ready!")
last_song_change = 0
while True:
	#print(last_song_change, playing_music)
	if os.path.isfile(filepath):
		with open(filepath,"r") as f:
			data = f.readlines()

		#print(data[0])

		clear()
		if "start" in data[0]:
			
			last_song_change = 0
			song = random.choice(songs)
			playing_music = song
			print("playing", song)
			mixer.Channel(0).play(mixer.Sound(song), fade_ms=1500)
			
		elif "stop" in data[0]:
			playing_music = False
			last_song_change = 0
			print("stop")
			mixer.Channel(0).stop()

	if playing_music and last_song_change > change_song_after:
		song = random.choice(songs)
		while playing_music == song:
			song = random.choice(songs)
		playing_music = song
		print("playing next song", song)
		mixer.Channel(0).fadeout(1000)
		mixer.Channel(0).play(mixer.Sound(song), fade_ms=1500)
		last_song_change = 0

	last_song_change += sleep_time
	time.sleep(sleep_time)
