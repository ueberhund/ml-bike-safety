# ml-bike-safety

This repo is designed to show how to realistically use machine learning to improve bike safety

Have you ever tried road cycling? I mean, really on the road? If you've never done it before, it can be scary. You quickly realize how many cars are on the road and how many drivers are not as attentive as they should be. Most road cyclists have had at least a few close calls. 

An emerging trend is for cyclists to run cameras on their bikes, so they can record any encounters they have. However, dealing with the video after the fact is time consuming and not very fun. This project aims to make it easy for cyclists to take their video and automatically produce videos of close encounters. They can then share these videos with proper individuals to make sure attitudes and behavors change out on the road.

To run this, you can simply run the install_stack.sh file. This script deploys 3 stacks, builds and deploys 2 docker containers, and sets up an ML model that supports vehicle detection. I created 3 different stacks just for convenience in deploying, but you should really think of the stacks as a single unit. They are just separate because (for example) I had to create an ECR repo and deploy a container before I could create a Fargate task. 

![architecture diagram](https://github.com/ueberhund/ml-bike-safety/blob/main/images/architecture.png)

The architecture works approximately as follows:
* You upload a video (or set of videos) to the ingest bucket
* A lambda function is triggered, which starts a step function (used for orchestration)
* The step function starts up two Fargate tasks, which:
  * Pull the videos down from the S3 bucket
  * Turn each frame of video into an image
  * Sends 2 images per second to SageMaker for batch inference (looking for vehicles in frame)
  * Performs geometry on the identified vehicle rectanges to determine if we have a "close call" with the bike
  * Any close calls are sent to MediaConvert to create short clips
  * The generated video clips are stored in S3 and a notification is sent out to the user

Once complete, you simply upload your video to the input bucket. The stack analyzes your video, and if there are any "close calls" with a vehicle, it will output a video and place it in the output bucket. You'll also receive a notification with a direct link to the video.

Safe cycling and keep the rubber side down!


NOTE: If you run this in Cloud9, make sure to double the size of the drive. One of the Docker images that is built is pretty big and will error out on Cloud9 if you don't give it at least 20GB of space.
