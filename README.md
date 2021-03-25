![Ordinary Experts Logo](https://ordinaryexperts.com/img/logo.png)

# Jitsi on AWS Pattern

The Ordinary Experts Jitsi Pattern is an open-source AWS CloudFormation template that offers an easy-to-install AWS infrastructure solution for quickly deploying a Jitsi service, using AWS best practices.

[Jitsi](https://jitsi.org/) is a set of free and open-source projects which allow easy building deployment of secure video conferencing solutions.

## Product Setup

*Prework*

For this pattern to work, you must first:

1. Have an AWS Route 53 Hosted Zone configured and delegated
1. Have at least 1 available EIP (or at least 2 available EIPs if not using your own VPC)

After that you can just launch the CloudFormation stack and fill out the required parameters.

See the [Ordinary Experts AWS Marketplace Product Page](https://ordinaryexperts.com/products/jitsi-pattern/) for a more detailed walkthrough with screenshots.

## Technical Details

* Ubuntu 18.04.4 LTS
* Apache 2.4.29
* Jitsi version 2.0.5390-3

The AWS stack uses Amazon Elastic Compute Cloud (Amazon EC2), Amazon Virtual Public Cloud (Amazon VPC), Amazon CloudWatch and Amazon Route 53.

While our solution manages its EC2 instance via an AWS AutoScaling Group to take advantage of the support for multiple availability zone configuration, it DOES NOT support load balancing or automatically scaling Jitsi application servers. Such a setup requires a custom load balancing setup and may be included in a future release of this product.

The template places a single EC2 instance in a public subnet of the VPC and secures port access to 80, 443, 4443 and 1000 via an EC2 Security Group. Users can optionally have the template create a brand new VPC, or specify an existing VPC ID in their AWS account into which to deploy, including subnet identification parameters. Users are also able to lock down public access of the service to an ingress CIDR Block, in case they want to restrict access to a range of IP addresses (such as corporate VPN IPs).

Optionally, users can provide an AWS Route 53 Hosted Zone Name and the stack will automatically manage a DNS record for the provided hostname parameter. This is the recommended setup. The AWS CloudFormation stack provides and EC2 Elastic IP address as an output, whose IP address should be pointed to by the DNS record input as the 'Jitsi Hostname' parameter.

**IMPORTANT**: As part of the Jitsi installation process, a [LetsEncrypt](https://letsencrypt.org/) certificate is generated, and the install process will try to validate the certificate programmatically every 12 minutes until it is successful. The installation will not be complete until DNS is pointing to the hostname supplied by parameter, and a certificate request has been successfully made.

Configuration of the Jitsi interface is possible via a number of parameters to the stack. Our solution automatically modifies `/usr/share/jitsi-meet/interface_config.js` to accommodate these customizations. Configuration of additional options is possible by modifying this file directly on the stack's application server. Please consult the Jitsi documentation for further reading on the configuration options. Options are subject to change with new releases of Jitsi and be aware that a manual upgrade of the Jitsi package on the EC2 instance will be overwritten upon new deployments.

Direct access to the EC2 instance for maintenance and customizations is possible through AWS Systems Manager Agent which is running as a service on the instance. For access, locate the EC2 instance in the AWS console dashboard, select it and click the "Connect" button, selecting the "Session Manager" option.

Regions supported by Ordinary Experts' stack:

| Fully Supported | Unsupported |
| -------------- | ----------- |
| <ul><li>us-east-1 (N. Virginia)</li><li>us-east-2 (Ohio)</li><li>us-west-1 (N. California)</li><li>us-west-2 (Oregon)</li><li>ca-central-1 (Central)</li><li>eu-central-1 (Frankfurt)</li><li>eu-north-1 (Stockholm)</li><li>eu-west-1 (Ireland)</li><li>eu-west-2 (London)</li><li>eu-west-3 (Paris)</li><li>ap-northeast-1 (Tokyo)</li><li>ap-northeast-2 (Seoul)</li><li>ap-south-1 (Mumbai)</li><li>ap-southeast-1 (Singapore)</li><li>ap-southeast-2 (Sydney)</li><li>sa-east-1 (Sao Paolo)</li></ul> | <ul><li>eu-south-1 (Milan)</li><li>ap-east-1 (Hong Kong)</li><li>me-south-1 (Bahrain)</li><li>af-south-1 (Cape Town)</li></ul> |

Optional configurations include the following:

* Contain your Jisti infrastructure in a new VPC, or provide this CloudFormation stack with an existing VPC id and subnets.
* Manage DNS automatically by supplying an AWS Route 53 Hosted Zone to the stack.
* Jitsi interface configuration via a number of parameters to the stack.

## Jitsi Stack Infrastructure

![Topology Diagram](https://ordinaryexperts.com/img/services/oe_jitsi_patterns_topology_diagram.png)

## Developer Setup

We are following the [3 Musketeers](https://3musketeers.io/) pattern for project layout / setup.

First, install [Docker](https://www.docker.com/), [Docker Compose](https://docs.docker.com/compose/), and [Make](https://www.gnu.org/software/make/).

## Feedback

To post feedback, submit feature ideas, or report bugs, use the [Issues section](https://github.com/ordinaryexperts/aws-marketplace-oe-patterns-jitsi/issues) of this GitHub repo.
