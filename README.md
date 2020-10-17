# ml-bike-safety

This repo is designed to show how to realistically use machine learning to improve bike safety

Have you ever tried road cycling? I mean, really on the road? If you've never done it before, it can be scary. You quickly realize how many cars are on the road and how many drivers are not as attentive as they should be. Most road cyclists have had at least a few close calls. 

An emerging trend is for cyclists to run cameras on their bikes, so they can record any encounters they have. However, dealing with the video after the fact is time consuming and not very fun. This project aims to make it easy for cyclists to take their video and automatically produce videos of close encounters. They can then share these videos with proper individuals to make sure attitudes and behavors change out on the road.

To run this, you can simply run the install_stack.sh file. This script deploys 3 stacks, builds and deploys 2 docker containers, and sets up an ML model that supports vehicle detection.

Once complete, you simply upload your video to the input bucket. The stack analyzes your video, and if there are any "close calls" with a vehicle, it will output a video and place it in the output bucket. You'll also receive a notification with a direct link to the video.

Safe cycling and keep the rubber side down!
