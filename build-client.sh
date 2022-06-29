#!/bin/sh
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

if [ $# -ne 1 ]; then
    echo "Usage: build-client.sh <s3 bucket name>"
    exit 1
fi

S3BUCKET=$1

if [ ! -x "$(which pip3)" ]; then
    echo "ERROR: pip3 not found or not executable.  Please make sure python3 and pip are installed."
    exit 1
fi

cd api-client/python-client-lambda
mkdir -p .build
echo "Installing python dependencies"
pip3 install -r requirements.txt --upgrade -t .build/
if [ $? -ne 0 ]; then exit 1; fi
cp *.py .build/

cd ..
echo "Packaging SAM templates into S3 bucket $S3BUCKET"
sam package --template-file api-client.yaml \
            --output-template-file api-client-deploy.yaml \
            --s3-bucket $S3BUCKET

sam package --template-file vpc-api-client.yaml \
            --output-template-file vpc-api-client-deploy.yaml \
            --s3-bucket $S3BUCKET




