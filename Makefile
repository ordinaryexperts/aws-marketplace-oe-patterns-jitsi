-include common.mk

update-common:
	wget -O common.mk https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/1.7.5/common.mk

deploy: build
	docker compose run -w /code/cdk --rm devenv cdk deploy \
	--require-approval never \
	--parameters AlbCertificateArn=arn:aws:acm:us-east-1:992593896645:certificate/943928d7-bfce-469c-b1bf-11561024580e \
	--parameters AlbIngressCidr=0.0.0.0/0 \
	--parameters AsgAmiIdv400=ami-002f46374624dcaee \
	--parameters AsgReprovisionString=20251120.1 \
	--parameters CustomDotEnvParameterArn=arn:aws:ssm:us-east-1:992593896645:parameter/oe-patterns-jitsi-dylan-custom-dot-env:4 \
	--parameters CustomConfigJsParameterArn=arn:aws:ssm:us-east-1:992593896645:parameter/oe-patterns-jitsi-dylan-custom-config-js:1 \
	--parameters CustomInterfaceConfigJsParameterArn=arn:aws:ssm:us-east-1:992593896645:parameter/oe-patterns-jitsi-dylan-custom-interface-config-js:1 \
	--parameters DnsHostname=jitsi-${USER}.dev.patterns.ordinaryexperts.com \
	--parameters DnsRoute53HostedZoneName=dev.patterns.ordinaryexperts.com
