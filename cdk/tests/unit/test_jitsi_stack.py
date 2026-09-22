import aws_cdk as core
import aws_cdk.assertions as assertions
from aws_cdk.assertions import Match

from jitsi.jitsi_stack import JitsiStack


def synth():
    app = core.App()
    stack = JitsiStack(app, "jitsi")
    return assertions.Template.from_stack(stack)


def test_asg_sg_allows_udp_10000_from_nlb_sg():
    t = synth()
    t.has_resource_properties("AWS::EC2::SecurityGroupIngress", Match.object_like({
        "IpProtocol": "udp",
        "FromPort": 10000,
        "ToPort": 10000,
        "GroupId": {"Ref": "AsgSg"},
        "SourceSecurityGroupId": {"Ref": "NlbSg"},
    }))


def test_asg_sg_allows_tcp_80_health_check_from_nlb_sg():
    # The NLB's UDP target groups health-check on TCP 80; those probes come
    # from the NLB security group and must be allowed into the ASG instances,
    # otherwise every UDP target is permanently unhealthy.
    t = synth()
    t.has_resource_properties("AWS::EC2::SecurityGroupIngress", Match.object_like({
        "IpProtocol": "tcp",
        "FromPort": 80,
        "ToPort": 80,
        "GroupId": {"Ref": "AsgSg"},
        "SourceSecurityGroupId": {"Ref": "NlbSg"},
    }))


def test_udp_target_groups_health_check_on_tcp_80():
    # JVB/Jigasi only listen on UDP, so the default health check (TCP on the
    # traffic port) can never succeed; the UDP target groups must probe nginx
    # on TCP 80 instead.
    t = synth()
    udp_tgs = t.find_resources("AWS::ElasticLoadBalancingV2::TargetGroup",
                               {"Properties": {"Protocol": "UDP"}})
    assert len(udp_tgs) == 1 + 41  # JVB 10000 + Jigasi 20000-20040
    for logical_id, tg in udp_tgs.items():
        props = tg["Properties"]
        assert props.get("HealthCheckProtocol") == "TCP", logical_id
        assert props.get("HealthCheckPort") == "80", logical_id
