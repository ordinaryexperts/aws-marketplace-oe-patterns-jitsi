FROM ubuntu:20.04

COPY setup-env.sh /tmp/setup-env.sh
RUN bash /tmp/setup-env.sh
RUN rm -f /tmp/setup-env.sh

# install dependencies
RUN mkdir -p /tmp/code/cdk/jitsi
COPY ./cdk/requirements.txt /tmp/code/cdk/
COPY ./cdk/setup.py /tmp/code/cdk/
RUN touch /tmp/code/cdk/README.md
WORKDIR /tmp/code/cdk
#RUN apt -y update && apt install -y python3-pip
RUN pip3 install --default-timeout=100 -r requirements.txt
RUN rm -rf /tmp/code