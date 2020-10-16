#!/usr/bin/env bash

echo "What is your email address (used for the SNS notification)?"
read EMAIL_ADDRESS

#Check to make sure all required commands are installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found"
    exit
fi

if ! command -v aws &> /dev/null
then
    echo "aws could not be found"
    exit
fi

if ! command -v docker &> /dev/null
then
    echo "docker could not be found"
    exit
fi

docker_state=$(docker info >/dev/null 2>&1)
if [[ $? -ne 0 ]]; then
    echo "Docker does not seem to be running, run it first and retry"
    exit
fi

STACK_NAME='video-infra'

REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity | jq '.Account' -r)

if [ -z "$REGION" ]; then
    echo "Please set a region by running 'aws configure'"
    exit
fi


echo "Creating stack..."
STACK_ID=$( aws cloudformation create-stack --stack-name ${STACK_NAME} \
  --template-body file://video-infrastructure.yml \
  --capabilities CAPABILITY_IAM \
  | jq -r .StackId \
)

echo "Waiting on ${STACK_ID} create completion..."
aws cloudformation wait stack-create-complete --stack-name ${STACK_ID}
CFN_OUTPUT=$(aws cloudformation describe-stacks --stack-name ${STACK_ID} | jq .Stacks[0].Outputs)

ML_BUCKET=$(echo $CFN_OUTPUT | jq '.[]| select(.OutputKey | contains("MLBucket")).OutputValue' -r)
VIDEO_INPUT_BUCKET=$(echo $CFN_OUTPUT | jq '.[] | select(.OutputKey | contains("VideoInputBucket")).OutputValue' -r)
VIDEO_OUTPUT_BUCKET=$(echo $CFN_OUTPUT | jq '.[] | select(.OutputKey | contains("VideoOutputBucket")).OutputValue' -r)
PUBLIC_SEC_GROUP=$(echo $CFN_OUTPUT | jq '.[] | select(.OutputKey | contains("PublicSecurityGroup")).OutputValue' -r)
VPC=$(echo $CFN_OUTPUT | jq '.[] | select(.OutputKey | contains("VPCId")).OutputValue' -r)
PUB_SUBNET_1=$(echo $CFN_OUTPUT | jq '.[] | select(.OutputKey | contains("PublicSubnet1")).OutputValue' -r)
PUB_SUBNET_2=$(echo $CFN_OUTPUT | jq '.[] | select(.OutputKey | contains("PublicSubnet2")).OutputValue' -r)
VIDEO_TO_FRAME_REPO=$(echo $CFN_OUTPUT | jq '.[] | select(.OutputKey | contains("VideoToFrameRepo")).OutputValue' -r)
VIDEO_INF_REPO=$(echo $CFN_OUTPUT | jq '.[] | select(.OutputKey | contains("VideoInferenceRepo")).OutputValue' -r)

#Upload the ML model_name
MODEL_PATH="s3://${ML_BUCKET}/model/model.tar.gz"
aws s3 cp s3://aws-gmike-public-us-west-2/video-processing-model/model.tar.gz ${MODEL_PATH}
#echo $MODEL_PATH

#If using a different region, you'll need to get the right path, available here:
#https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-algo-docker-registry-paths.html
SAGEMAKER_ECR_PATH=''
readonly paths=(
      'us-west-2|433757028032.dkr.ecr.us-west-2.amazonaws.com'
      'us-east-1|811284229777.dkr.ecr.us-east-1.amazonaws.com'
      'us-east-2|825641698319.dkr.ecr.us-east-2.amazonaws.com'
      'eu-central-1|813361260812.dkr.ecr.eu-central-1.amazonaws.com'
      'eu-north-1|669576153137.dkr.ecr.eu-north-1.amazonaws.com'
      'eu-west-1|685385470294.dkr.ecr.eu-west-1.amazonaws.com'
      'eu-west-2|644912444149.dkr.ecr.eu-west-2.amazonaws.com'
      'eu-west-3|749696950732.dkr.ecr.eu-west-3.amazonaws.com'
)

for fields in ${paths[@]}
do
  IFS=$'|' read -r region_code url <<< "$fields"
  if [ "$region_code" = "$REGION" ]; then
    SAGEMAKER_ECR_PATH=$url
  fi
done

SAGEMAKER_ECR_PATH="${SAGEMAKER_ECR_PATH}/object-detection:1"
#echo $SAGEMAKER_ECR_PATH

ML_STACK_NAME="${STACK_NAME}-ml-model"

ML_STACK_ID=$( aws cloudformation create-stack --stack-name ${ML_STACK_NAME} \
  --template-body file://video-resources.yml \
  --parameters ParameterKey=ImageUrl,ParameterValue=${SAGEMAKER_ECR_PATH} \
               ParameterKey=ModelPath,ParameterValue=${MODEL_PATH} \
               ParameterKey=EmailAddress,ParameterValue=${EMAIL_ADDRESS} \
  --capabilities CAPABILITY_IAM \
  | jq -r .StackId \
)

echo "Waiting on ${ML_STACK_ID} create completion..."
aws cloudformation wait stack-create-complete --stack-name ${ML_STACK_ID}
RESOURCE_OUTPUT=$(aws cloudformation describe-stacks --stack-name ${ML_STACK_ID} | jq .Stacks[0].Outputs)
MODEL_NAME=$(echo $RESOURCE_OUTPUT | jq '.[] | select(.OutputKey | contains("Model")).OutputValue' -r)
SNS_TOPIC=$(echo $RESOURCE_OUTPUT | jq '.[] | select(.OutputKey | contains("SNSTopic")).OutputValue' -r)
MEDIACONVERT_SERVICE_ROLE=$(echo $RESOURCE_OUTPUT | jq '.[] | select(.OutputKey | contains("MediaConvertServiceRole")).OutputValue' -r)
echo $MODEL_NAME
echo $SNS_TOPIC
echo $MEDIACONVERT_SERVICE_ROLE

#Transform the code in the docker images
MEDIACONVERT_ENDPOINT_URL=$(aws mediaconvert describe-endpoints | jq '.[][0].Url' -r)
echo $MEDIACONVERT_ENDPOINT_URL

#Build and upload the docker images
echo "Building video-to-frame docker image"
DOCKER_URL_1=$(aws ecr describe-repositories | jq '.repositories[] | select(.repositoryName | contains("'$VIDEO_TO_FRAME_REPO'")).repositoryUri' -r)

cd docker/video-to-frame/
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
docker build -t $VIDEO_TO_FRAME_REPO .
docker tag $VIDEO_TO_FRAME_REPO:latest $DOCKER_URL_1:1
docker push $DOCKER_URL_1:1

echo "Building the video-inference docker image"
DOCKER_URL_2=$(aws ecr describe-repositories | jq '.repositories[] | select(.repositoryName | contains("'$VIDEO_INF_REPO'")).repositoryUri' -r)
echo $DOCKER_URL_2
cd ../video-inference
cp video-inference.py.orig video-inference.py
sed -i -e "s~<SNS_TOPIC_ARN>~$SNS_TOPIC~g" video-inference.py
sed -i -e "s~<MEDIACONVERT_ENDPOINT_URL>~${MEDIACONVERT_ENDPOINT_URL}~g" video-inference.py
sed -i -e "s~<MEDIACONVERT_SERVICE_ROLE>~${MEDIACONVERT_SERVICE_ROLE}~g" video-inference.py
sed -i -e "s~<ML_MODEL_NAME>~$MODEL_NAME~g" video-inference.py

docker build -t $VIDEO_INF_REPO .
docker tag $VIDEO_INF_REPO:latest $DOCKER_URL_2:1
docker push $DOCKER_URL_2:1

#Deploy the rest of the stack
echo "Building the Fargate tasks and step functions"
cd ../..
STEP_STACK_NAME="${STACK_NAME}-compute"
STEP_STACK_ID=$( aws cloudformation create-stack --stack-name ${STEP_STACK_NAME} \
  --template-body file://video-processing.yml \
  --parameters ParameterKey=VideoToFrameContainer,ParameterValue=${DOCKER_URL_1}:1 \
               ParameterKey=VideoInferenceContainer,ParameterValue=${DOCKER_URL_2}:1 \
  --capabilities CAPABILITY_IAM \
  | jq -r .StackId \
)

aws cloudformation wait stack-create-complete --stack-name ${STEP_STACK_ID}

echo "Congratulations! Your stack is now complete!"
echo "You can begin by uploading a file to s3://${VIDEO_INPUT_BUCKET}"
