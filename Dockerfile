FROM ordinaryexperts/aws-marketplace-patterns-devenv:2.8.3
# For local testing, build from local devenv
# FROM aws-marketplace-patterns-devenv

# install dependencies
RUN mkdir -p /tmp/code/cdk/jitsi
COPY ./cdk/requirements.txt /tmp/code/cdk/
COPY ./cdk/setup.py /tmp/code/cdk/
RUN touch /tmp/code/cdk/README.md
WORKDIR /tmp/code/cdk
RUN pip3 install --break-system-packages -r requirements.txt
RUN rm -rf /tmp/code
