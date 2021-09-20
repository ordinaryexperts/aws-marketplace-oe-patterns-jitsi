import json
import os
import subprocess
import yaml
from aws_cdk import (
    aws_autoscaling,
    aws_ec2,
    aws_elasticloadbalancingv2,
    aws_iam,
    aws_logs,
    aws_route53,
    aws_sns,
    core
)

from oe_patterns_cdk_common import Vpc

TWO_YEARS_IN_DAYS=731
if 'TEMPLATE_VERSION' in os.environ:
    template_version = os.environ['TEMPLATE_VERSION']
else:
    try:
        template_version = subprocess.check_output(["git", "describe"]).strip().decode('ascii')
    except:
        template_version = "CICD"

# When making a new development AMI:
# 1) $ ave oe-patterns-dev make ami-ec2-build
# 2) $ ave oe-patterns-dev make AMI_ID=ami-fromstep1 ami-ec2-copy
# 3) Copy the code that copy-image generates below

# AMI list generated by:
# make TEMPLATE_VERSION=2.0.0 ami-ec2-build
# on Sun Apr 25 15:12:58 UTC 2021.
AMI_ID="ami-0e80b8232adc37e71"
AMI_NAME="ordinary-experts-patterns-jitsi-1.0.1-20201006-0513"
generated_ami_ids = {
    "ap-northeast-1": "ami-XXXXXXXXXXXXXXXXX",
    "ap-northeast-2": "ami-XXXXXXXXXXXXXXXXX",
    "ap-south-1": "ami-XXXXXXXXXXXXXXXXX",
    "ap-southeast-1": "ami-XXXXXXXXXXXXXXXXX",
    "ap-southeast-2": "ami-XXXXXXXXXXXXXXXXX",
    "ca-central-1": "ami-XXXXXXXXXXXXXXXXX",
    "eu-central-1": "ami-XXXXXXXXXXXXXXXXX",
    "eu-north-1": "ami-XXXXXXXXXXXXXXXXX",
    "eu-west-1": "ami-XXXXXXXXXXXXXXXXX",
    "eu-west-2": "ami-XXXXXXXXXXXXXXXXX",
    "eu-west-3": "ami-XXXXXXXXXXXXXXXXX",
    "sa-east-1": "ami-XXXXXXXXXXXXXXXXX",
    "us-east-2": "ami-XXXXXXXXXXXXXXXXX",
    "us-west-1": "ami-XXXXXXXXXXXXXXXXX",
    "us-west-2": "ami-XXXXXXXXXXXXXXXXX",
    "us-east-1": "ami-0e80b8232adc37e71"
}
# End generated code block.

# Sanity check: if this fails then make copy-image needs to be run...
assert AMI_ID == generated_ami_ids["us-east-1"]

class JitsiStack(core.Stack):

    def __init__(self, scope: core.Construct, id: str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        current_directory = os.path.realpath(os.path.join(os.getcwd(), os.path.dirname(__file__)))
        allowed_values = yaml.load(
            open(os.path.join(current_directory, "allowed_values.yaml")),
            Loader=yaml.SafeLoader
        )
        ami_mapping={
            "AMI": {
                "OEJITSI": AMI_NAME
            }
        }
        for region in generated_ami_ids.keys():
            ami_mapping[region] = { "OEJITSI": generated_ami_ids[region] }
        aws_ami_region_map = core.CfnMapping(
            self,
            "AWSAMIRegionMap",
            mapping=ami_mapping
        )

        # utility function to parse the unique id from the stack id for
        # shorter resource names  using cloudformation functions
        def append_stack_uuid(name):
            return core.Fn.join("-", [
                name,
                core.Fn.select(0, core.Fn.split("-", core.Fn.select(2, core.Fn.split("/", core.Aws.STACK_ID))))
            ])

        #
        # PARAMETERS
        #

        cidr_block_param = core.CfnParameter(
            self,
            "IngressCidrBlock",
            allowed_pattern="((\d{1,3})\.){3}\d{1,3}/\d{1,2}",
            default="0.0.0.0/0",
            description="Required: A CIDR block to restrict access to the Jitsi application. Leave as 0.0.0.0/0 to allow public access from internet."
        )
        ec2_instance_type_param = core.CfnParameter(
            self,
            "InstanceType",
            allowed_values=allowed_values["allowed_instance_types"],
            default="t3.xlarge",
            description="Required: The EC2 instance type for the application Auto Scaling Group."
        )
        jitsi_hostname_param = core.CfnParameter(
            self,
            "JitsiHostname",
            description="Required: The hostname to access Jitsi. E.G. 'jitsi.internal.mycompany.com'"
        )
        jitsi_interface_app_name_param = core.CfnParameter(
            self,
            "JitsiInterfaceAppName",
            default="Jitsi Meet",
            description="Optional: Customize the app name on the Jitsi interface."
        )
        jitsi_interface_default_remote_display_name_param = core.CfnParameter(
            self,
            "JitsiInterfaceDefaultRemoteDisplayName",
            default="Fellow Jitster",
            description="Optional: Customize the default display name for Jitsi users."
        )
        jitsi_interface_native_app_name_param = core.CfnParameter(
            self,
            "JitsiInterfaceNativeAppName",
            default="Jitsi Meet",
            description="Optional: Customize the native app name on the Jitsi interface."
        )
        jitsi_interface_show_brand_watermark_param = core.CfnParameter(
            self,
            "JitsiInterfaceShowBrandWatermark",
            allowed_values=[ "true", "false" ],
            default="true",
            description="Optional: Display the watermark logo image in the upper left corner."
        )
        jitsi_interface_show_watermark_for_guests_param = core.CfnParameter(
            self,
            "JitsiInterfaceShowWatermarkForGuests",
            allowed_values=[ "true", "false" ],
            default="true",
            description="Optional: Display the watermark logo image in the upper left corner for guest users. This can be set to override the general setting behavior for guest users."
        )
        jitsi_interface_brand_watermark_param = core.CfnParameter(
            self,
            "JitsiInterfaceBrandWatermark",
            default="",
            description="Optional: Provide a URL to a PNG image to be used as the brand watermark logo image in the upper right corner. File should be publically available for download."
        )
        jitsi_interface_brand_watermark_link_param = core.CfnParameter(
            self,
            "JitsiInterfaceBrandWatermarkLink",
            default="http://jitsi.org",
            description="Optional: Provide a link destination for the brand watermark logo image in the upper right corner."
        )
        jitsi_interface_watermark_param = core.CfnParameter(
            self,
            "JitsiInterfaceWatermark",
            default="",
            description="Optional: Provide a URL to a PNG image to be used as the watermark logo image in the upper left corner. File should be publically available for download."
        )
        jitsi_interface_watermark_link_param = core.CfnParameter(
            self,
            "JitsiInterfaceWatermarkLink",
            default="http://jitsi.org",
            description="Optional: Provide a link destination for the Jitsi watermark logo image in the upper left corner."
        )
        route_53_hosted_zone_name_param = core.CfnParameter(
            self,
            "Route53HostedZoneName",
            description="Required: Route 53 Hosted Zone name in which a DNS record will be created by this template. Must already exist and be the domain part of the Jitsi Hostname parameter, without trailing dot. E.G. 'internal.mycompany.com'"
        )
        notification_email_param = core.CfnParameter(
            self,
            "NotificationEmail",
            default="",
            description="Optional: Specify an email address to get emails about deploys, Let's Encrypt, and other system events."
        )

        #
        # CONDITIONS
        #

        notification_email_exists_condition = core.CfnCondition(
            self,
            "NotificationEmailExistsCondition",
            expression=core.Fn.condition_not(core.Fn.condition_equals(notification_email_param.value, ""))
        )

        #
        # RESOURCES
        #

        # vpc
        vpc = Vpc(
            self,
            "Vpc"
        )

        # sns
        sns_notification_topic = aws_sns.CfnTopic(
            self,
            "NotificationTopic",
            topic_name="{}-notifications".format(core.Aws.STACK_NAME)
        )
        sns_notification_subscription = aws_sns.CfnSubscription(
            self,
            "NotificationSubscription",
            protocol="email",
            topic_arn=sns_notification_topic.ref,
            endpoint=notification_email_param.value_as_string
        )
        sns_notification_subscription.cfn_options.condition = notification_email_exists_condition
        iam_notification_publish_policy = aws_iam.PolicyDocument(
            statements=[
                aws_iam.PolicyStatement(
                    effect=aws_iam.Effect.ALLOW,
                    actions=[ "sns:Publish" ],
                    resources=[ sns_notification_topic.ref ]
                )
            ]
        )

        # cloudwatch
        app_log_group = aws_logs.CfnLogGroup(
            self,
            "JitsiAppLogGroup",
            retention_in_days=TWO_YEARS_IN_DAYS
        )
        app_log_group.cfn_options.update_replace_policy = core.CfnDeletionPolicy.RETAIN
        app_log_group.cfn_options.deletion_policy = core.CfnDeletionPolicy.RETAIN
        system_log_group = aws_logs.CfnLogGroup(
            self,
            "JitsiSystemLogGroup",
            retention_in_days=TWO_YEARS_IN_DAYS
        )
        system_log_group.cfn_options.update_replace_policy = core.CfnDeletionPolicy.RETAIN
        system_log_group.cfn_options.deletion_policy = core.CfnDeletionPolicy.RETAIN

        # iam
        iam_jitsi_instance_role = aws_iam.CfnRole(
            self,
            "JitsiInstanceRole",
            assume_role_policy_document=aws_iam.PolicyDocument(
                statements=[
                    aws_iam.PolicyStatement(
                        effect=aws_iam.Effect.ALLOW,
                        actions=[ "sts:AssumeRole" ],
                        principals=[ aws_iam.ServicePrincipal("ec2.amazonaws.com") ]
                    )
                ]
            ),
            policies=[
                aws_iam.CfnRole.PolicyProperty(
                    policy_document=aws_iam.PolicyDocument(
                        statements=[
                            aws_iam.PolicyStatement(
                                effect=aws_iam.Effect.ALLOW,
                                actions=[
                                    "logs:CreateLogStream",
                                    "logs:DescribeLogStreams",
                                    "logs:PutLogEvents"
                                ],
                                resources=[
                                    system_log_group.attr_arn
                                ]
                            )
                        ]
                    ),
                    policy_name="AllowStreamLogsToCloudWatch"
                ),
                aws_iam.CfnRole.PolicyProperty(
                    policy_document=aws_iam.PolicyDocument(
                        statements=[
                            aws_iam.PolicyStatement(
                                effect=aws_iam.Effect.ALLOW,
                                actions=[
                                    "ec2:AssociateAddress",
                                    "ec2:DescribeVolumes",
                                    "ec2:DescribeTags",
                                    "cloudwatch:GetMetricStatistics",
                                    "cloudwatch:ListMetrics",
                                    "cloudwatch:PutMetricData"
                                ],
                                resources=[ "*" ]
                            )
                        ]
                    ),
                    policy_name="AllowStreamMetricsToCloudWatch"
                ),
                aws_iam.CfnRole.PolicyProperty(
                    policy_document=aws_iam.PolicyDocument(
                        statements=[
                            aws_iam.PolicyStatement(
                                effect=aws_iam.Effect.ALLOW,
                                actions=[ "autoscaling:Describe*" ],
                                resources=[ "*" ]
                            )
                        ]
                    ),
                    policy_name="AllowDescribeAutoScaling"
                ),
            ],
            managed_policy_arns=[
                "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
            ]
        )

        # ec2
        jitsi_sg = aws_ec2.CfnSecurityGroup(
            self,
            "JitsiSg",
            group_description="Jitsi security group",
            vpc_id=vpc.id()
        )

        eip = aws_ec2.CfnEIP(
            self,
            "Eip",
            domain="vpc"
        )
        core.Tag.add(eip, "Name", "{}/Eip".format(core.Aws.STACK_NAME))

        ec2_instance_profile = aws_iam.CfnInstanceProfile(
	    self,
	    "JitsiInstanceProfile",
            roles=[ iam_jitsi_instance_role.ref ]
        )
        with open("jitsi/jitsi_launch_config_user_data.sh") as f:
            jitsi_launch_config_user_data = f.read()
        ec2_launch_config = aws_autoscaling.CfnLaunchConfiguration(
            self,
            "JitsiLaunchConfig",
            image_id=core.Fn.find_in_map("AWSAMIRegionMap", core.Aws.REGION, "OEJITSI"),
            instance_type=ec2_instance_type_param.value_as_string,
            iam_instance_profile=ec2_instance_profile.ref,
            security_groups=[ jitsi_sg.ref ],
            user_data=(
                core.Fn.base64(
                    core.Fn.sub(
                        jitsi_launch_config_user_data,
                        {
                            "JitsiHostname": jitsi_hostname_param.value_as_string,
                            "JitsiPublicIP": eip.ref,
                            "LetsEncryptCertificateEmail": notification_email_param.value_as_string
                        }
                    )
                )
            )
        )

        # autoscaling
        asg = aws_autoscaling.CfnAutoScalingGroup(
            self,
            "JitsiAsg",
            launch_configuration_name=ec2_launch_config.ref,
            desired_capacity="1",
            max_size="1",
            min_size="1",
            vpc_zone_identifier=vpc.public_subnet_ids()
        )
        asg.cfn_options.creation_policy=core.CfnCreationPolicy(
            resource_signal=core.CfnResourceSignal(
                count=1,
                timeout="PT15M"
            )
        )
        asg.cfn_options.update_policy=core.CfnUpdatePolicy(
            auto_scaling_rolling_update=core.CfnAutoScalingRollingUpdate(
                max_batch_size=1,
                min_instances_in_service=0,
                pause_time="PT15M",
                wait_on_resource_signals=True
            )
        )
        core.Tag.add(asg, "Name", "{}/JitsiAsg".format(core.Aws.STACK_NAME))

        jitsi_http_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "JitsiHttpSgIngress",
            cidr_ip=cidr_block_param.value_as_string,
            from_port=80,
            group_id=jitsi_sg.ref,
            ip_protocol="tcp",
            to_port=80
        )
        jitsi_https_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "JitsiHttpsSgIngress",
            cidr_ip=cidr_block_param.value_as_string,
            from_port=443,
            group_id=jitsi_sg.ref,
            ip_protocol="tcp",
            to_port=443
        )
        jitsi_fallback_network_audio_video_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "JitsiFallbackNetworkAudioVideoSgIngress",
            cidr_ip=cidr_block_param.value_as_string,
            from_port=4443,
            group_id=jitsi_sg.ref,
            ip_protocol="tcp",
            to_port=4443
        )
        jitsi_general_network_audio_video_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "JitsiGeneralNetworkAudioVideoSgIngress",
            cidr_ip=cidr_block_param.value_as_string,
            from_port=10000,
            group_id=jitsi_sg.ref,
            ip_protocol="udp",
            to_port=10000
        )

        # route 53
        record_set = aws_route53.CfnRecordSet(
            self,
            "RecordSet",
            hosted_zone_name=f"{route_53_hosted_zone_name_param.value_as_string}.",
            name=jitsi_hostname_param.value_as_string,
            resource_records=[ eip.ref ],
            type="A"
        )
        # https://github.com/aws/aws-cdk/issues/8431
        record_set.add_property_override("TTL", 60)

        # AWS::CloudFormation::Interface
        self.template_options.metadata = {
            "OE::Patterns::TemplateVersion": template_version,
            "AWS::CloudFormation::Interface": {
                "ParameterGroups": [
                    {
                        "Label": {
                            "default": "Infrastructure Config"
                        },
                        "Parameters": [
                            jitsi_hostname_param.logical_id,
                            route_53_hosted_zone_name_param.logical_id,
                            cidr_block_param.logical_id,
                            ec2_instance_type_param.logical_id,
                            notification_email_param.logical_id
                        ]
                    },
                    {
                        "Label": {
                            "default": "Jitsi Config"
                        },
                        "Parameters": [
                            jitsi_interface_app_name_param.logical_id,
                            jitsi_interface_default_remote_display_name_param.logical_id,
                            jitsi_interface_native_app_name_param.logical_id,
                            jitsi_interface_show_brand_watermark_param.logical_id,
                            jitsi_interface_show_watermark_for_guests_param.logical_id,
                            jitsi_interface_brand_watermark_param.logical_id,
                            jitsi_interface_brand_watermark_link_param.logical_id,
                            jitsi_interface_watermark_param.logical_id,
                            jitsi_interface_watermark_link_param.logical_id,
                        ]
                    },
                    *vpc.metadata_parameter_group()
                ],
                "ParameterLabels": {
                    cidr_block_param.logical_id: {
                        "default": "Ingress CIDR Block"
                    },
                    ec2_instance_type_param.logical_id: {
                        "default": "EC2 instance type"
                    },
                    jitsi_hostname_param.logical_id: {
                        "default": "Jitsi Hostname"
                    },
                    jitsi_interface_app_name_param.logical_id: {
                        "default": "Jitsi Interface App Name"
                    },
                    jitsi_interface_default_remote_display_name_param.logical_id: {
                        "default": "Jitsi Interface Default Remote Display Name"
                    },
                    jitsi_interface_native_app_name_param.logical_id: {
                        "default": "Jitsi Interface Native App Name"
                    },
                    jitsi_interface_show_brand_watermark_param.logical_id: {
                        "default": "Jitsi Interface Show Watermark"
                    },
                    jitsi_interface_show_watermark_for_guests_param.logical_id: {
                        "default": "Jitsi Interface Show Watermark For Guests"
                    },
                    jitsi_interface_brand_watermark_param.logical_id: {
                        "default": "Jitsi Interface Watermark"
                    },
                    jitsi_interface_brand_watermark_link_param.logical_id: {
                        "default": "Jitsi Interface Watermark Link"
                    },
                    jitsi_interface_watermark_param.logical_id: {
                        "default": "Jitsi Interface Watermark"
                    },
                    jitsi_interface_watermark_link_param.logical_id: {
                        "default": "Jitsi Interface Watermark Link"
                    },
                    notification_email_param.logical_id: {
                        "default": "Notification Email"
                    },
                    route_53_hosted_zone_name_param.logical_id: {
                        "default": "AWS Route 53 Hosted Zone Name"
                    },
                    **vpc.metadata_parameter_labels()
                }
            }
        }

        #
        # OUTPUTS
        #

        eip_output = core.CfnOutput(
            self,
            "EipOutput",
            description="The Elastic IP address dynamically mapped to the autoscaling group instance.",
            value=eip.ref
        )
        endpoint_output = core.CfnOutput(
            self,
            "JitsiUrl",
            description="The URL for the Jitsi instance.",
            value=core.Fn.join("", ["https://", jitsi_hostname_param.value_as_string])
        )
