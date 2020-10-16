sed -i -e 's~<SNS_TOPIC_ARN>~arn:aws:sns:us-west-2:122554519915:video_notification~g' video-inference.py
sed -i -e 's~<MEDIACONVERT_ENDPOINT_URL>~https:\/\/mlboolfjb.mediaconvert.us-west-2.amazonaws.com~g' video-inference.py
sed -i -e 's~<MEDIACONVERT_SERVICE_ROLE>~arn:aws:iam::122554519915:role\/MediaConvert-ServiceRole~g' video-inference.py
sed -i -e 's~<ML_MODEL_NAME>~vehicle-classification-gopro~g' video-inference.py
