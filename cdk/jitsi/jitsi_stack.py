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
    aws_sns,
    core
)

from oe_patterns_cdk_common import Vpc

TWO_YEARS_IN_DAYS=731
# TODO: uncomment after a release
#template_version = subprocess.check_output(["git", "describe"]).strip().decode('ascii')
template_version = "0.0"

# When making a new development AMI:
# 1) $ ave oe-patterns-dev make ami-ec2-build
# 2) $ ave oe-patterns-dev make AMI_ID=ami-fromstep1 ami-ec2-copy
# 3) Copy the code that copy-image generates below

# AMI list generated by:
# make AMI_ID=ami-00b66504cb32b04b8 ami-ec2-copy
# on Fri Jul  3 15:23:50 UTC 2020.
AMI_ID="ami-00b66504cb32b04b8"
AMI_NAME="ordinary-experts-patterns-jitsi--20200703-0313"
generated_ami_ids = {
    "us-east-2": "ami-0f46f62bf8bc3fba6",
    "us-west-1": "ami-09fe64e23cc6ea62b",
    "us-west-2": "ami-0adb46b642a6c46b9",
    "ca-central-1": "ami-06c57c0b8cf034f63",
    "eu-central-1": "ami-06d11a4d10ba41c94",
    "eu-north-1": "ami-0237acef50a57bb7a",
    "eu-west-1": "ami-00b269904806a9343",
    "eu-west-2": "ami-0c6508476addc2d0c",
    "eu-west-3": "ami-045e1cef41c12c508",
    "ap-northeast-1": "ami-0bc6ea3be1b70e6ff",
    "ap-northeast-2": "ami-034d4bca1a93ce1b7",
    "ap-south-1": "ami-0c8d9ae8dd32b3442",
    "ap-southeast-1": "ami-0a7c63cebfe0d8544",
    "ap-southeast-2": "ami-0d3ea4cbc009058fa",
    "sa-east-1": "ami-03a115aee2e04f377",
    "us-east-1": "ami-00b66504cb32b04b8"
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

        acm_certificate_arn_param = core.CfnParameter(
            self,
            "CertificateArn",
            default="",
            description="Optional: Specify the ARN of a ACM Certificate to configure HTTPS."
        )
        autoscaling_desired_capacity_param = core.CfnParameter(
            self,
            "JitsiAsgDesiredCapacity",
            default=1,
            description="Required: The desired capacity of the Auto Scaling Group.",
            min_value=0,
            type="Number"
        )
        autoscaling_max_size_param = core.CfnParameter(
            self,
            "JitsiAsgMaxSize",
            default=2,
            description="Required: The maximum size of the Auto Scaling Group.",
            min_value=0,
            type="Number"
        )
        autoscaling_min_size_param = core.CfnParameter(
            self,
            "JitsiAsgMinSize",
            default=1,
            description="Required: The minimum size of the Auto Scaling Group.",
            min_value=0,
            type="Number"
        )
        ec2_instance_type_param = core.CfnParameter(
            self,
            "InstanceType",
            default="t3.xlarge",
            description="Required: The EC2 instance type for the application Auto Scaling Group."
        )
        jitsi_hostname_param = core.CfnParameter(
            self,
            "JitsiHostname",
            description="Required: The DNS hostname configured to access Jitsi."
        )
        lets_encrypt_certificate_email_param = core.CfnParameter(
            self,
            "LetsEncryptCertificateEmail",
            description="Required: The email address to use for Let's Encrypt certificate validation."
        )
        sns_notification_email_param = core.CfnParameter(
            self,
            "NotificationEmail",
            default="",
            description="Optional: Specify an email address to get emails about deploys and other system events."
        )
        vpc_cidr_block_param = core.CfnParameter(
            self,
            "VpcCidrBlock",
            default="",
            description="Optional: Specify the VPC CIDR block."
        )

        #
        # CONDITIONS
        #
        
        acm_certificate_arn_exists_condition = core.CfnCondition(
            self,
            "CertificateArnExists",
            expression=core.Fn.condition_not(core.Fn.condition_equals(acm_certificate_arn_param.value, ""))
        )
        acm_certificate_arn_does_not_exist_condition = core.CfnCondition(
            self,
            "CertificateArnNotExists",
            expression=core.Fn.condition_equals(acm_certificate_arn_param.value, "")
        )
        sns_notification_email_exists_condition = core.CfnCondition(
            self,
            "NotificationEmailExists",
            expression=core.Fn.condition_not(core.Fn.condition_equals(sns_notification_email_param.value, ""))
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
            endpoint=sns_notification_email_param.value_as_string
        )
        sns_notification_subscription.cfn_options.condition = sns_notification_email_exists_condition
        iam_notification_publish_policy =aws_iam.PolicyDocument(
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
                            "LetsEncryptCertificateEmail": lets_encrypt_certificate_email_param.value_as_string
                        }
                    )
                )
            )
        )

        nlb_sg = aws_ec2.CfnSecurityGroup(
            self,
            "NlbSg",
            group_description="Nlb Sg",
            vpc_id=vpc.id()
        )
        nlb_http_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "NlbSgHttpIngress",
            cidr_ip="0.0.0.0/0",
            description="Allow from anyone on port 80",
            from_port=80,
            group_id=nlb_sg.ref,
            ip_protocol="tcp",
            to_port=80
        )
        nlb_https_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "NlbSgHttpsIngress",
            cidr_ip="0.0.0.0/0",
            description="Allow from anyone on port 443",
            from_port=443,
            group_id=nlb_sg.ref,
            ip_protocol="tcp",
            to_port=443
        )
        nlb_fallback_network_audio_video_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "NlbFallbackNetworkAudioVideoIngressSg",
            cidr_ip="0.0.0.0/0",
            description="Allow from anyone on port 4443",
            from_port=4443,
            group_id=nlb_sg.ref,
            ip_protocol="tcp",
            to_port=4443
        )
        nlb_general_network_audio_video_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "NlbGeneralNetworkAudioVideoIngressSg",
            cidr_ip="0.0.0.0/0",
            description="Allow from anyone on port 1000",
            from_port=1000,
            group_id=nlb_sg.ref,
            ip_protocol="udp",
            to_port=1000
        )

        # TODO: parameterize and conditionalize cidr_ip
        jitsi_http_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "JitsiHttpSgIngress",
            # TODO: integrate Vpc CIDR into cdk-common or find way to reference
            cidr_ip=core.Token.as_string(
                core.Fn.condition_if(
                    vpc.given_condition.logical_id,
                    vpc_cidr_block_param.value_as_string,
                    vpc.vpc.attr_cidr_block
                )
            ),
            from_port=80,
            group_id=jitsi_sg.ref,
            ip_protocol="tcp",
            to_port=80
        )
        jitsi_https_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "JitsiHttpsSgIngress",
            # TODO: integrate Vpc CIDR into cdk-common or find way to reference
            cidr_ip=core.Token.as_string(
                core.Fn.condition_if(
                    vpc.given_condition.logical_id,
                    vpc_cidr_block_param.value_as_string,
                    vpc.vpc.attr_cidr_block
                )
            ),
            from_port=443,
            group_id=jitsi_sg.ref,
            ip_protocol="tcp",
            to_port=443
        )
        jitsi_fallback_network_audio_video_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "JitsiFallbackNetworkAudioVideoSgIngress",
            # TODO: integrate Vpc CIDR into cdk-common or find way to reference
            cidr_ip=core.Token.as_string(
                core.Fn.condition_if(
                    vpc.given_condition.logical_id,
                    vpc_cidr_block_param.value_as_string,
                    vpc.vpc.attr_cidr_block
                )
            ),
            from_port=4443,
            group_id=jitsi_sg.ref,
            ip_protocol="tcp",
            to_port=4443
        )
        jitsi_general_network_audio_video_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "JitsiGeneralNetworkAudioVideoSgIngress",
            # TODO: integrate Vpc CIDR into cdk-common or find way to reference
            cidr_ip=core.Token.as_string(
                core.Fn.condition_if(
                    vpc.given_condition.logical_id,
                    vpc_cidr_block_param.value_as_string,
                    vpc.vpc.attr_cidr_block
                )
            ),
            from_port=1000,
            group_id=jitsi_sg.ref,
            ip_protocol="udp",
            to_port=1000
        )

        # elasticloadbalancing
        nlb = aws_elasticloadbalancingv2.CfnLoadBalancer(
            self,
            "AppNlb",
            scheme="internet-facing",
            subnets=vpc.public_subnet_ids(),
            type="network"
        )
        http_target_group = aws_elasticloadbalancingv2.CfnTargetGroup(
            self,
            "AsgHttpTargetGroup",
            health_check_enabled=None,
            health_check_interval_seconds=None,
            port=80,
            protocol="TCP",
            target_type="instance",
            vpc_id=vpc.id()
        )
        http_listener = aws_elasticloadbalancingv2.CfnListener(
            self,
            "HttpListener",
            default_actions=[
                aws_elasticloadbalancingv2.CfnListener.ActionProperty(
                    target_group_arn=http_target_group.ref,
                    type="forward"
                )
            ],
            load_balancer_arn=nlb.ref,
            port=80,
            protocol="TCP"
        )
        https_target_group = aws_elasticloadbalancingv2.CfnTargetGroup(
            self,
            "AsgHttpsTargetGroup",
            health_check_enabled=None,
            health_check_interval_seconds=None,
            port=443,
            protocol="TLS",
            target_type="instance",
            vpc_id=vpc.id()
        )
        https_listener = aws_elasticloadbalancingv2.CfnListener(
            self,
            "HttpsListener",
            certificates=[
                aws_elasticloadbalancingv2.CfnListener.CertificateProperty(
                    certificate_arn=acm_certificate_arn_param.value_as_string
                )
            ],
            default_actions=[
                aws_elasticloadbalancingv2.CfnListener.ActionProperty(
                    target_group_arn=https_target_group.ref,
                    type="forward"
                )
            ],
            load_balancer_arn=nlb.ref,
            port=443,
            protocol="TLS"
        )
        fallback_network_audio_video_target_group = aws_elasticloadbalancingv2.CfnTargetGroup(
            self,
            "FallbackNetworkAudioVideoTargetGroup",
            health_check_enabled=None,
            health_check_interval_seconds=None,
            port=4443,
            protocol="TCP",
            target_type="instance",
            vpc_id=vpc.id()
        )
        fallback_network_audio_video_listener = aws_elasticloadbalancingv2.CfnListener(
            self,
            "FallbackNetworkAudioVideoListener",
            default_actions=[
                aws_elasticloadbalancingv2.CfnListener.ActionProperty(
                    target_group_arn=fallback_network_audio_video_target_group.ref,
                    type="forward"
                )
            ],
            load_balancer_arn=nlb.ref,
            port=4443,
            protocol="TCP"
        )
        general_network_audio_video_target_group = aws_elasticloadbalancingv2.CfnTargetGroup(
            self,
            "GeneralNetworkAudioVideoTargetGroup",
            health_check_enabled=None,
            health_check_interval_seconds=None,
            port=1000,
            protocol="UDP",
            target_type="instance",
            vpc_id=vpc.id()
        )
        general_network_audio_video_listener = aws_elasticloadbalancingv2.CfnListener(
            self,
            "GeneralNetworkAudioVideoListener",
            default_actions=[
                aws_elasticloadbalancingv2.CfnListener.ActionProperty(
                    target_group_arn=general_network_audio_video_target_group.ref,
                    type="forward"
                )
            ],
            load_balancer_arn=nlb.ref,
            port=1000,
            protocol="UDP"
        )

        # autoscaling
        asg = aws_autoscaling.CfnAutoScalingGroup(
            self,
            "JitsiAsg",
            launch_configuration_name=ec2_launch_config.ref,
            desired_capacity=core.Token.as_string(autoscaling_desired_capacity_param.value),
            max_size=core.Token.as_string(autoscaling_max_size_param.value),
            min_size=core.Token.as_string(autoscaling_min_size_param.value),
            target_group_arns=[
                http_target_group.ref,
                https_target_group.ref
            ],
            vpc_zone_identifier=vpc.private_subnet_ids()
        )
        asg.cfn_options.creation_policy=core.CfnCreationPolicy(
            resource_signal=core.CfnResourceSignal(
                count=1,
                timeout="PT15M"
            )
        )
        asg.cfn_options.update_policy=core.CfnUpdatePolicy(
            auto_scaling_rolling_update=core.CfnAutoScalingRollingUpdate(
                min_instances_in_service=1,
                pause_time="PT15M",
                wait_on_resource_signals=True
            ),
            auto_scaling_scheduled_action=core.CfnAutoScalingScheduledAction(
                ignore_unmodified_group_size_properties=True
            )
        )
        core.Tag.add(asg, "Name", "{}/JitsiAsg".format(core.Aws.STACK_NAME))

        # AWS::CloudFormation::Interface
        self.template_options.metadata = {
            "OE::Patterns::TemplateVersion": template_version,
            "AWS::CloudFormation::Interface": {
                "ParameterGroups": [
                    {
                        "Label": {
                            "default": "Application Config"
                        },
                        "Parameters": [
                            acm_certificate_arn_param.logical_id
                        ]
                    },
                    vpc.metadata_parameter_group()
                ],
                "ParameterLabels": {
                    sns_notification_email_param.logical_id: {
                        "default": "Notification Email"
                    },
                    **vpc.metadata_parameter_labels()
                }
            }
        }

        #
        # OUTPUTS
        #
