import os
import subprocess
import yaml
from aws_cdk import (
    Aws,
    aws_autoscaling,
    aws_ec2,
    aws_elasticloadbalancingv2,
    aws_iam,
    aws_logs,
    aws_route53,
    aws_sns,
    CfnAutoScalingRollingUpdate,
    CfnCondition,
    CfnCreationPolicy,
    CfnDeletionPolicy,
    CfnMapping,
    CfnOutput,
    CfnParameter,
    CfnResourceSignal,
    CfnUpdatePolicy,
    Fn,
    Stack,
    Tags
)
from constructs import Construct

from oe_patterns_cdk_common.asg import Asg
from oe_patterns_cdk_common.vpc import Vpc

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

AMI_ID="ami-0655acd20bbda9332"
AMI_NAME="ordinary-experts-patterns-jitsi-1.0.0-20230712-0246"
generated_ami_ids = {
    "us-east-1": "ami-0655acd20bbda9332"
}
# End generated code block.

# Sanity check: if this fails then make copy-image needs to be run...
assert AMI_ID == generated_ami_ids["us-east-1"]

class JitsiStack(Stack):

    def __init__(self, scope: Construct, id: str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        current_directory = os.path.realpath(os.path.join(os.getcwd(), os.path.dirname(__file__)))
        allowed_values = yaml.load(
            open(os.path.join(current_directory, "..", "..", "allowed_values.yaml")),
            Loader=yaml.SafeLoader
        )
        ami_mapping={
            "AMI": {
                "AMI": AMI_NAME
            }
        }
        for region in generated_ami_ids.keys():
            ami_mapping[region] = { "AMI": generated_ami_ids[region] }
        aws_ami_region_map = CfnMapping(
            self,
            "AWSAMIRegionMap",
            mapping=ami_mapping
        )

        # utility function to parse the unique id from the stack id for
        # shorter resource names  using cloudformation functions
        def append_stack_uuid(name):
            return Fn.join("-", [
                name,
                Fn.select(0, Fn.split("-", Fn.select(2, Fn.split("/", Aws.STACK_ID))))
            ])

        #
        # PARAMETERS
        #

        cidr_block_param = CfnParameter(
            self,
            "IngressCidrBlock",
            allowed_pattern="((\d{1,3})\.){3}\d{1,3}/\d{1,2}",
            default="0.0.0.0/0",
            description="Required: A CIDR block to restrict access to the Jitsi application. Leave as 0.0.0.0/0 to allow public access from internet."
        )
        jitsi_hostname_param = CfnParameter(
            self,
            "JitsiHostname",
            description="Required: The hostname to access Jitsi. E.G. 'jitsi.internal.mycompany.com'"
        )
        jitsi_interface_app_name_param = CfnParameter(
            self,
            "JitsiInterfaceAppName",
            default="Jitsi Meet",
            description="Optional: Customize the app name on the Jitsi interface."
        )
        jitsi_interface_default_remote_display_name_param = CfnParameter(
            self,
            "JitsiInterfaceDefaultRemoteDisplayName",
            default="Fellow Jitster",
            description="Optional: Customize the default display name for Jitsi users."
        )
        jitsi_interface_native_app_name_param = CfnParameter(
            self,
            "JitsiInterfaceNativeAppName",
            default="Jitsi Meet",
            description="Optional: Customize the native app name on the Jitsi interface."
        )
        jitsi_interface_show_brand_watermark_param = CfnParameter(
            self,
            "JitsiInterfaceShowBrandWatermark",
            allowed_values=[ "true", "false" ],
            default="true",
            description="Optional: Display the watermark logo image in the upper left corner."
        )
        jitsi_interface_show_watermark_for_guests_param = CfnParameter(
            self,
            "JitsiInterfaceShowWatermarkForGuests",
            allowed_values=[ "true", "false" ],
            default="true",
            description="Optional: Display the watermark logo image in the upper left corner for guest users. This can be set to override the general setting behavior for guest users."
        )
        jitsi_interface_brand_watermark_param = CfnParameter(
            self,
            "JitsiInterfaceBrandWatermark",
            default="",
            description="Optional: Provide a URL to a PNG image to be used as the brand watermark logo image in the upper right corner. File should be publically available for download."
        )
        jitsi_interface_brand_watermark_link_param = CfnParameter(
            self,
            "JitsiInterfaceBrandWatermarkLink",
            default="http://jitsi.org",
            description="Optional: Provide a link destination for the brand watermark logo image in the upper right corner."
        )
        jitsi_interface_watermark_param = CfnParameter(
            self,
            "JitsiInterfaceWatermark",
            default="",
            description="Optional: Provide a URL to a PNG image to be used as the watermark logo image in the upper left corner. File should be publically available for download."
        )
        jitsi_interface_watermark_link_param = CfnParameter(
            self,
            "JitsiInterfaceWatermarkLink",
            default="http://jitsi.org",
            description="Optional: Provide a link destination for the Jitsi watermark logo image in the upper left corner."
        )
        route_53_hosted_zone_name_param = CfnParameter(
            self,
            "Route53HostedZoneName",
            description="Required: Route 53 Hosted Zone name in which a DNS record will be created by this template. Must already exist and be the domain part of the Jitsi Hostname parameter, without trailing dot. E.G. 'internal.mycompany.com'"
        )

        #
        # RESOURCES
        #

        # vpc
        vpc = Vpc(
            self,
            "Vpc"
        )

        certificate_arn_param = CfnParameter(
            self,
            "CertificateArn",
            description="Specify the ARN of an ACM Certificate to configure HTTPS."
        )

        nlb = aws_elasticloadbalancingv2.CfnLoadBalancer(
            self,
            "Nlb",
            scheme="internet-facing",
            subnets=vpc.public_subnet_ids(),
            type="network"
        )

        http_target_group = aws_elasticloadbalancingv2.CfnTargetGroup(
            self,
            "HttpTargetGroup",
            port=80,
            protocol="TCP",
            target_type="instance",
            vpc_id=vpc.id()
        )


        https_target_group = aws_elasticloadbalancingv2.CfnTargetGroup(
            self,
            "HttpsTargetGroup",
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
                    certificate_arn=certificate_arn_param.value_as_string
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
        fallback_target_group = aws_elasticloadbalancingv2.CfnTargetGroup(
            self,
            "FallbackTargetGroup",
            port=4443,
            protocol="TCP",
            target_type="instance",
            vpc_id=vpc.id()
        )
        fallback_listener = aws_elasticloadbalancingv2.CfnListener(
            self,
            "FallbackListener",
            default_actions=[
                aws_elasticloadbalancingv2.CfnListener.ActionProperty(
                    target_group_arn=fallback_target_group.ref,
                    type="forward"
                )
            ],
            load_balancer_arn=nlb.ref,
            port=4443,
            protocol="TCP"
        )
        jitsi_target_group = aws_elasticloadbalancingv2.CfnTargetGroup(
            self,
            "JitsiTargetGroup",
            port=10000,
            protocol="UDP",
            target_type="instance",
            vpc_id=vpc.id()
        )
        jitsi_listener = aws_elasticloadbalancingv2.CfnListener(
            self,
            "JitsiListener",
            default_actions=[
                aws_elasticloadbalancingv2.CfnListener.ActionProperty(
                    target_group_arn=jitsi_target_group.ref,
                    type="forward"
                )
            ],
            load_balancer_arn=nlb.ref,
            port=10000,
            protocol="UDP"
        )

        with open("jitsi/user_data.sh") as f:
            user_data = f.read()
        asg = Asg(
            self,
            "Asg",
            default_instance_type = "t3.xlarge",
            use_graviton = False,
            user_data_contents=user_data,
            user_data_variables = {
                'JitsiHostname': jitsi_hostname_param.value_as_string
            },
            vpc=vpc
        )
        asg.asg.target_group_arns = [
            http_target_group.ref,
            https_target_group.ref,
            fallback_target_group.ref,
            jitsi_target_group.ref
        ]

        jitsi_http_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "JitsiHttpSgIngress",
            cidr_ip=cidr_block_param.value_as_string,
            from_port=80,
            group_id=asg.sg.ref,
            ip_protocol="tcp",
            to_port=80
        )
        jitsi_https_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "JitsiHttpsSgIngress",
            cidr_ip=cidr_block_param.value_as_string,
            from_port=443,
            group_id=asg.sg.ref,
            ip_protocol="tcp",
            to_port=443
        )
        jitsi_fallback_network_audio_video_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "JitsiFallbackNetworkAudioVideoSgIngress",
            cidr_ip=cidr_block_param.value_as_string,
            from_port=4443,
            group_id=asg.sg.ref,
            ip_protocol="tcp",
            to_port=4443
        )
        jitsi_general_network_audio_video_ingress = aws_ec2.CfnSecurityGroupIngress(
            self,
            "JitsiGeneralNetworkAudioVideoSgIngress",
            cidr_ip=cidr_block_param.value_as_string,
            from_port=10000,
            group_id=asg.sg.ref,
            ip_protocol="udp",
            to_port=10000
        )

        record_set = aws_route53.CfnRecordSet(
            self,
            "RecordSet",
            hosted_zone_name=f"{route_53_hosted_zone_name_param.value_as_string}.",
            name=jitsi_hostname_param.value_as_string,
            resource_records=[ nlb.attr_dns_name ],
            type="CNAME"
        )
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
                            cidr_block_param.logical_id
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
                    *asg.metadata_parameter_group(),
                    *vpc.metadata_parameter_group()
                ],
                "ParameterLabels": {
                    cidr_block_param.logical_id: {
                        "default": "Ingress CIDR Block"
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
                    route_53_hosted_zone_name_param.logical_id: {
                        "default": "AWS Route 53 Hosted Zone Name"
                    },
                    **asg.metadata_parameter_labels(),
                    **vpc.metadata_parameter_labels()
                }
            }
        }

        #
        # OUTPUTS
        #

        endpoint_output = CfnOutput(
            self,
            "JitsiUrl",
            description="The URL for the Jitsi instance.",
            value=Fn.join("", ["https://", jitsi_hostname_param.value_as_string])
        )
