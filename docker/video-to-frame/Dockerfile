FROM python:3.7

RUN apt-get update
RUN apt-get install -y libgl1-mesa-dev

RUN pip install --upgrade pip

# set a directory for the app
WORKDIR /usr/src/app

# copy all the files to the container
COPY . .

# install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# tell the port number the container should expose
EXPOSE 5000

# run the command
CMD ["python", "./video-to-frame.py"]
