#!/usr/bin/env python3
# Copyright 2023 Chris Farris <chris@primeharbor.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import boto3
import csv
import argparse
from datetime import datetime, timedelta, timezone

parser = argparse.ArgumentParser(description="Download GuardDuty findings from all AWS regions.")
parser.add_argument("--days", type=int, required=True, help="How many days back to look for findings")
parser.add_argument("--outfile", type=str, required=True, help="Output CSV file name")
args = parser.parse_args()

days_back = args.days
outfile = args.outfile
cutoff = datetime.now(timezone.utc) - timedelta(days=days_back)

session = boto3.Session()

# Get only enabled regions
enabled_regions = []
region_client = session.client("ec2")
for region_info in region_client.describe_regions(AllRegions=False)["Regions"]:
    if region_info["OptInStatus"] in ("opt-in-not-required", "opted-in"):
        enabled_regions.append(region_info["RegionName"])

fields = [
    "Finding ID",
    "Title",
    "Severity",
    "Severity Score",
    "Finding Type",
    "Count of Events",
    "AWS Account ID",
    "Created At",
    "Updated At",
    "Region",
]

results = []

def severity_label(score):
    if score == 9.0:
        return "Critical"
    elif score >= 7.0:
        return "High"
    elif score >= 4.0:
        return "Medium"
    elif score >= 0.1:
        return "Low"
    else:
        return "Informational"

for region in enabled_regions:
    client = session.client("guardduty", region_name=region)
    try:
        detectors = client.list_detectors()["DetectorIds"]
        if not detectors:
            continue
        detector_id = detectors[0]

        paginator = client.get_paginator("list_findings")
        finding_ids = []

        for page in paginator.paginate(DetectorId=detector_id):
            finding_ids.extend(page["FindingIds"])

        print(f"Got Total of {len(finding_ids)} Findings in {region}")

        if not finding_ids:
            continue

        for i in range(0, len(finding_ids), 50):  # GuardDuty batch limit is 50
            batch = finding_ids[i:i+50]
            findings = client.get_findings(DetectorId=detector_id, FindingIds=batch)["Findings"]

            for finding in findings:
                updated_at = datetime.fromisoformat(finding["UpdatedAt"])
                if updated_at < cutoff:
                    continue
                score = finding.get("Severity", 0)
                results.append({
                    "Finding ID": finding.get("Id", ""),
                    "Title": finding.get("Title", ""),
                    "Severity": severity_label(score),
                    "Severity Score": score,
                    "Finding Type": finding.get("Type", ""),
                    "Count of Events": finding.get("Service", {}).get("Count", 1),
                    "AWS Account ID": finding.get("AccountId", ""),
                    "Created At": finding.get("CreatedAt", ""),
                    "Updated At": finding.get("UpdatedAt", ""),
                    "Region": region,
                })
    except client.exceptions.ClientError as e:
        print(f"Error processing region {region}: {e}")

with open(outfile, mode="w", newline="") as csvfile:
    writer = csv.DictWriter(csvfile, fieldnames=fields)
    writer.writeheader()
    writer.writerows(results)

print(f"Wrote {len(results)} findings from the last {days_back} days to {outfile}")