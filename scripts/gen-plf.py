# gen-plf.py
# ----------
#
# Generates a row suitable for submitting to AWS Marketplace in their Product Load Form

import awspricing
import csv
import re
import yaml

OE_MARKUP_PERCENTAGE = 0.05
ANNUAL_SAVINGS_PERCENTAGE = 0.80 # 20% off
MINIMUM_RATE = 0.001
HOURS_IN_A_YEAR = 8760
DEFAULT_REGION = "us-east-1"

# to generate the 'gen-plf-column-headers.txt', open the Excel Product Load Form,
# select header row, copy & paste into txt file, replacing all contents.
column_headers = open("/code/scripts/gen-plf-column-headers.txt").read().rstrip().split("\t")

plf_config = yaml.load(
    open("/code/plf_config.yaml"),
    Loader=yaml.SafeLoader
)
plf_values = {}

allowed_values = yaml.load(
    open("/code/cdk/jitsi/allowed_values.yaml"),
    Loader=yaml.SafeLoader
)

allowed_instance_types = allowed_values["allowed_instance_types"]
allowed_regions = allowed_values["allowed_regions"]

# list copied from scripts/copy-image.sh
# TODO: move to YAML

allowed_regions = [
    "us-east-2",
    "us-west-1",
    "us-west-2",
    "ca-central-1",
    "eu-central-1",
    "eu-north-1",
    "eu-west-1",
    "eu-west-2",
    "eu-west-3",
    "ap-northeast-1",
    "ap-northeast-2",
    "ap-south-1",
    "ap-southeast-1",
    "ap-southeast-2",
    "sa-east-1"
]
# plus our default region
allowed_regions.append(DEFAULT_REGION)

ec2_offer = awspricing.offer('AmazonEC2')

for header in column_headers:

    availability_match = re.search(r"(.+) Availability", header)
    if availability_match:
        match_keyword = availability_match.groups()[0]
        # region or instance availability?
        is_instance_match = re.search(r"^(.+)\.(.+)$", match_keyword)
        if is_instance_match:
            if match_keyword in allowed_instance_types:
                plf_values[header] = "TRUE"
            else:
                plf_values[header] = "FALSE"
        else:
            if match_keyword in allowed_regions:
                plf_values[header] = "TRUE"
            else:
                plf_values[header] = "FALSE"

    price_match = re.search(r"(.+) (Hourly|Annual) Price", header)
    if price_match:
        instance_type = price_match.groups()[0]
        if instance_type in allowed_instance_types:
            price_type = price_match.groups()[1]
            price = ec2_offer.ondemand_hourly(
                instance_type,
                operating_system="Linux",
                tenancy="Shared",
                license_model="No License required",
                preinstalled_software="NA",
                region=DEFAULT_REGION,
                capacity_status="Used"
            )
            hourly_price_with_markup = price * OE_MARKUP_PERCENTAGE
            if price_type == "Hourly":
                if hourly_price_with_markup > MINIMUM_RATE:
                    plf_values[header] = str(round(hourly_price_with_markup, 3))
                else:
                    plf_values[header] = MINIMUM_RATE
            else:
                annual_price = hourly_price_with_markup * HOURS_IN_A_YEAR * ANNUAL_SAVINGS_PERCENTAGE
                plf_values[header] = str(round(annual_price, 2))
    if not availability_match and not price_match:
        if header in plf_config:
            plf_values[header] = plf_config[header]
        else:
            plf_values[header] = ""

with open('/code/pfl.csv', 'w', newline='') as csvfile:
    writer = csv.DictWriter(csvfile, fieldnames=column_headers)
    writer.writeheader()
    writer.writerow(plf_values)

print("PLF row saved to 'pfl.csv'")
