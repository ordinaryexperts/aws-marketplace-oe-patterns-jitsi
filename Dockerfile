FROM ordinaryexperts/aws-marketplace-patterns-devenv:2.5.3

# install dependencies
RUN mkdir -p /tmp/code/cdk/jitsi
COPY ./cdk/requirements.txt /tmp/code/cdk/
COPY ./cdk/setup.py /tmp/code/cdk/
RUN touch /tmp/code/cdk/README.md
WORKDIR /tmp/code/cdk
RUN pip3 install -r requirements.txt
RUN rm -rf /tmp/code
