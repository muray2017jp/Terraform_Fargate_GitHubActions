#!/bin/bash

set -e

TF_DIR="laravel-fargate-infra/envs/prod/app/foobar"

echo "=============================="
echo "Move to Terraform directory"
echo "=============================="

cd $TF_DIR

echo ""
echo "Current directory:"
pwd

echo ""
echo "=============================="
echo "Terraform Managed Resources"
echo "=============================="

terraform state list

echo ""
echo "=============================="
echo "Resource Details"
echo "=============================="

for r in $(terraform state list); do
  echo ""
  echo "------------------------------"
  echo "$r"
  echo "------------------------------"
  terraform state show $r
done
