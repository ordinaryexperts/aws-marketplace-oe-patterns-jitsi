![Ordinary Experts Logo](https://ordinaryexperts.com/img/logo.png)

# Jitsi Meet on AWS Pattern

The Ordinary Experts Jitsi Pattern is an open-source AWS CloudFormation template that offers an easy-to-install AWS infrastructure solution for quickly deploying a Jitsi Meet service, using AWS best practices.

[Jitsi Meet](https://jitsi.org/) is a set of free and open-source projects which allow easy building deployment of secure video conferencing solutions.

## Product Setup

*Prework*

For this pattern to work, you must first:

1. Have an AWS Route 53 Hosted Zone configured and delegated

After that you can just launch the CloudFormation stack and fill out the required parameters.

See the [Ordinary Experts AWS Marketplace Product Page](https://ordinaryexperts.com/products/jitsi-pattern/) for a more detailed walkthrough with screenshots.

## Technical Details

* Ubuntu 22.04.4 LTS
* Jitsi version stable-9823

The AWS stack uses Amazon Elastic Compute Cloud (Amazon EC2), Amazon Virtual Public Cloud (Amazon VPC), Amazon CloudWatch and Amazon Route 53.

The template places an EC2 instance in a private subnet of the VPC and secures port access to 80, 443, 4443 and 1000 via an EC2 Security Group. Users can optionally have the template create a brand new VPC, or specify an existing VPC ID in their AWS account into which to deploy, including subnet identification parameters. Users are also able to lock down public access of the service to an ingress CIDR Block, in case they want to restrict access to a range of IP addresses (such as corporate VPN IPs).

Users provide an AWS Route 53 Hosted Zone Name and the stack will automatically manage a DNS record for the provided hostname parameter.

Configuration of the Jitsi interface is possible via a number of parameters to the stack. Our solution automatically modifies `/usr/share/jitsi-meet/interface_config.js` to accommodate these customizations. Configuration of additional options is possible by modifying this file directly on the stack's application server. Please consult the Jitsi documentation for further reading on the configuration options. Options are subject to change with new releases of Jitsi and be aware that a manual upgrade of the Jitsi package on the EC2 instance will be overwritten upon new deployments.

Direct access to the EC2 instance for maintenance and customizations is possible through AWS Systems Manager Agent which is running as a service on the instance. For access, locate the EC2 instance in the AWS console dashboard, select it and click the "Connect" button, selecting the "Session Manager" option.

Optional configurations include the following:

* Contain your Jisti infrastructure in a new VPC, or provide this CloudFormation stack with an existing VPC id and subnets.
* Manage DNS automatically by supplying an AWS Route 53 Hosted Zone to the stack.

## Jitsi Stack Infrastructure

![Topology Diagram](https://ordinaryexperts.com/img/services/oe_jitsi_patterns_topology_diagram.png)

## Developer Setup

We are following the [3 Musketeers](https://3musketeers.io/) pattern for project layout / setup.

First, install [Docker](https://www.docker.com/), [Docker Compose](https://docs.docker.com/compose/), and [Make](https://www.gnu.org/software/make/).

## Feedback

To post feedback, submit feature ideas, or report bugs, use the [Issues section](https://github.com/ordinaryexperts/aws-marketplace-oe-patterns-jitsi/issues) of this GitHub repo.
