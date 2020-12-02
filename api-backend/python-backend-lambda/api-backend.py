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
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE
import json
import boto3
import os
from botocore.exceptions import ClientError

ddb_client = boto3.resource('dynamodb')
ddb_table = ddb_client.Table(os.environ['DDB_TABLE'])

def handler(event, context):
    print(json.dumps(event, default=str))
    requestContext = event['requestContext']
    requestId = requestContext['requestId']

    # Add an id key and write the request context to DDB
    requestContext['id'] = requestId
    try:
        ddb_table.put_item(Item=requestContext)
    except ClientError as err:
        # Just log the error if it fails
        print('ERROR: dynamodb put_item failed: {}: {}'.format(type(err), err))
    
    identity = requestContext['identity']
    return {'body': json.dumps(identity), 'statusCode': 200}