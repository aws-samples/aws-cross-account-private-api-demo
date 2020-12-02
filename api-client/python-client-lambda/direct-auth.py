# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import os
import json
import boto3
import re
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
import requests
from botocore.exceptions import ClientError
from boto3 import session
from aws_lambda_powertools import Logger

logger = Logger(service="python-api-client")

AWS_REGION = os.environ['AWS_REGION']
API_HOST = os.environ['API_HOST']
API_PREFIX = os.environ['API_PREFIX']
VPCE_DNS_NAMES = os.environ['VPCE_DNS_NAMES']
API_TIMEOUT = float(os.environ['API_TIMEOUT'])
PRIVATE_DNS_ENABLED = os.environ['PRIVATE_DNS_ENABLED']

API_URL = "https://" + API_HOST + API_PREFIX
if PRIVATE_DNS_ENABLED.lower() == 'false':
    # Use the appropriate VPC endpoint DNS name instead.
    # Look for the endpoint name that is not AZ specific.  The list is not
    # ordered so we need to search through each name.
    for endpoint in VPCE_DNS_NAMES.split(','):
        dist,name = endpoint.split(':', maxsplit=1)
        if re.match(r'^vpce-[a-z0-9]+-[a-z0-9]+\.execute-api\.', name):
            VPCE_DNS = name
            break
    API_URL = "https://" + VPCE_DNS + API_PREFIX

sts_client = boto3.client('sts')

def lambda_handler(event, context):
    # Initialise a request object to use for signing.
    # Make sure we're targetting the right API gateway host in the HTTP header,
    # especially required if the VPC endpoint DNS name is being used.
    logger.info("initialising API request to %s (host %s)", API_URL, API_HOST)
    request = AWSRequest(method="GET", url=API_URL, headers={'host':API_HOST})

    # Obtain credentials and use them to sign the request
    logger.info('retrieving current session and role credentials')
    sess = session.Session()
    credentials = sess.get_credentials()

    sigv4 = SigV4Auth(credentials, 'execute-api', AWS_REGION)
    sigv4.add_auth(request)

    prepreq = request.prepare()
    logger.info("making request to url %s", prepreq.url)
    response = requests.get(prepreq.url, headers=prepreq.headers, timeout=API_TIMEOUT)
    logger.info("response code: %d", response.status_code)
    logger.info("response text: %s", response.text)
    return {'statusCode': response.status_code, 'body': response.text}
