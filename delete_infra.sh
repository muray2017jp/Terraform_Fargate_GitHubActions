#!/bin/bash

set -e

BASE_DIR="laravel-fargate-infra/envs/prod"

cd $BASE_DIR/app/foobar && terraform destroy -auto-approve
cd ../../routing/appfoobar_link && terraform destroy -auto-approve
cd ../../cache/foobar && terraform destroy -auto-approve
cd ../../db/foobar && terraform destroy -auto-approve

cd ../../log/db_foobar && terraform destroy -auto-approve
cd ../app_foobar && terraform destroy -auto-approve
cd ../alb && terraform destroy -auto-approve

cd ../../network/main && terraform destroy -auto-approve