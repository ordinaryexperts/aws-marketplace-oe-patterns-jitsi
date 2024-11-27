-include common.mk

update-common:
	wget -O common.mk https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/1.6.0/common.mk

deploy: build
	docker compose run -w /code/cdk --rm devenv cdk deploy \
	--require-approval never \
	--parameters AlbCertificateArn=arn:aws:acm:us-east-1:992593896645:certificate/943928d7-bfce-469c-b1bf-11561024580e \
	--parameters AlbIngressCidr=0.0.0.0/0 \
	--parameters AsgReprovisionString=20241123.1 \
	--parameters CustomDotEnvParameterArn=arn:aws:ssm:us-east-1:992593896645:parameter/oe-patterns-jitsi-dylan-custom-dot-env:4 \
	--parameters CustomConfigJsParameterArn=arn:aws:ssm:us-east-1:992593896645:parameter/oe-patterns-jitsi-dylan-custom-config-js:1 \
	--parameters CustomInterfaceConfigJsParameterArn=arn:aws:ssm:us-east-1:992593896645:parameter/oe-patterns-jitsi-dylan-custom-interface-config-js:1 \
	--parameters DnsHostname=jitsi-${USER}.dev.patterns.ordinaryexperts.com \
	--parameters DnsRoute53HostedZoneName=dev.patterns.ordinaryexperts.com \
	--parameters VpcId=vpc-00425deda4c835455 \
	--parameters VpcPrivateSubnet1Id=subnet-030c94b9795c6cb96 \
	--parameters VpcPrivateSubnet2Id=subnet-079290412ce63c4d5 \
	--parameters VpcPublicSubnet1Id=subnet-0c2f5d4daa1792c8d \
	--parameters VpcPublicSubnet2Id=subnet-060c39a6ded9e89d7
