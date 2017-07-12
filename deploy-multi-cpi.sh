#!/usr/bin/env bash

function generate_az_env_file {
  local AWS_ACCESS_KEY=$1
  local AWS_SECRET_KEY=$2

  local az1_env_name=$3
  local az1_region=$4

  local az2_env_name=$5
  local az2_region=$6

  # generate ssh key pair
  [[ -f "${output_dir}/key" ]] || ssh-keygen -b 4096 -t rsa -f "${output_dir}/key" -P ""
  local public_key=$( cat "${output_dir}/key.pub" )


  cat > "${output_dir}/${az1_env_name}.env" <<EOF
  export ENV_NAME=${az1_env_name}
  export AWS_ACCESS_KEY=${AWS_ACCESS_KEY}
  export AWS_SECRET_KEY=${AWS_SECRET_KEY}
  export AWS_REGION=${az1_region}
  export AWS_PUBLIC_KEY="${public_key}"
EOF

  cat > "${output_dir}/${az2_env_name}.env" <<EOF
  export ENV_NAME=${az2_env_name}
  export AWS_ACCESS_KEY=${AWS_ACCESS_KEY}
  export AWS_SECRET_KEY=${AWS_SECRET_KEY}
  export AWS_REGION=${az2_region}
  export AWS_PUBLIC_KEY="${public_key}"
EOF
}

function teardown_iaas {
  local env_file=$1
  local vpc_cidr_block=$2 # e.g. 10.0.0.0/16

  source "${env_file}"

  echo "Destroying environment '${ENV_NAME}' with vpc cidr '${vpc_cidr_block}'."
  terraform destroy \
    -var "access_key=${AWS_ACCESS_KEY}" \
    -var "secret_key=${AWS_SECRET_KEY}" \
    -var "region=${AWS_REGION}" \
    -var "env_name=${ENV_NAME}" \
    -var "public_key=${AWS_PUBLIC_KEY}" \
    -var "vpc_cidr_block=${vpc_cidr_block}" \
    -state="${output_dir}/${ENV_NAME}.tfstate" \
    -force
}

function setup_iaas {
  local env_file=$1
  local vpc_cidr_block=$2 # e.g. 10.0.0.0/16

  source "${env_file}"

  echo "Creating environment '${ENV_NAME}' with vpc cidr '${vpc_cidr_block}'."
  terraform apply \
    -var "access_key=${AWS_ACCESS_KEY}" \
    -var "secret_key=${AWS_SECRET_KEY}" \
    -var "region=${AWS_REGION}" \
    -var "env_name=${ENV_NAME}" \
    -var "public_key=${AWS_PUBLIC_KEY}" \
    -var "vpc_cidr_block=${vpc_cidr_block}" \
    -state="${output_dir}/${ENV_NAME}.tfstate"

  local terraform_output_metadata="${output_dir}/terraform-metadata-${ENV_NAME}.json"
  jq -e --raw-output \
    '.modules[0].outputs | map_values(.value)' \
    "${ENV_NAME}.tfstate" > "${terraform_output_metadata}"
  echo "Terraform output metadata: ${terraform_output_metadata}"

  # Generate CPI Config ops file
  local cpi_config_ops_file="${output_dir}/cpi-config-ops-${ENV_NAME}.yml"
  bosh2 int \
    -l "${terraform_output_metadata}" \
    -v "access_key_id=${AWS_ACCESS_KEY}" \
    -v "secret_access_key=${AWS_SECRET_KEY}" \
    -v "env_name=${ENV_NAME}" \
    ops/multi-cpi-aws-ops.yml > "${cpi_config_ops_file}"
  echo "Generated CPI config ops file for '${ENV_NAME}'."

  # Generate Cloud Config ops file
  local cloud_config_ops_file="${output_dir}/cloud-config-ops-${ENV_NAME}.yml"
  bosh2 int \
    -l "${terraform_output_metadata}" \
    -v "env_name=${ENV_NAME}" \
    ops/cloud-config-ops.yml > "${cloud_config_ops_file}"

  local manifest_ops_file="${output_dir}/manifest-ops-${ENV_NAME}.yml"
  bosh2 int -v "env_name=${ENV_NAME}" ops/manifest-ops.yml > "${manifest_ops_file}"
  echo "Generated deployment manifest ops file for '${ENV_NAME}'."
}

function delete_director {
  local env_file=$1
  source "${env_file}"

  local terraform_output_metadata="${output_dir}/terraform-metadata-${ENV_NAME}.json"

  bosh2 -n delete-env \
    -o ~/workspace/bosh-deployment/aws/cpi.yml \
    -o ~/workspace/bosh-deployment/jumpbox-user.yml \
    -o ~/workspace/bosh-deployment/external-ip-with-registry-not-recommended.yml \
    -o ops/multi-cpi-director-aws-ops.yml \
    -l "${output_dir}/key.yml" \
    -l "${terraform_output_metadata}" \
    -v "access_key_id=${AWS_ACCESS_KEY}" \
    -v "secret_access_key=${AWS_SECRET_KEY}" \
    -v director_name="multi-cpi-bosh" \
    --vars-store "${output_dir}/creds.yml" \
    ~/workspace/bosh-deployment/bosh.yml

  echo "director-deleted" > "${output_dir}/director-deleted"
}

function deploy_director {
  local env_file=$1
  source "${env_file}"

  local terraform_output_metadata="${output_dir}/terraform-metadata-${ENV_NAME}.json"

  bosh2 -n create-env \
    -o ~/workspace/bosh-deployment/aws/cpi.yml \
    -o ~/workspace/bosh-deployment/jumpbox-user.yml \
    -o ~/workspace/bosh-deployment/external-ip-with-registry-not-recommended.yml \
    -o ops/multi-cpi-director-aws-ops.yml \
    -l "${output_dir}/key.yml" \
    -l "${terraform_output_metadata}" \
    -v "access_key_id=${AWS_ACCESS_KEY}" \
    -v "secret_access_key=${AWS_SECRET_KEY}" \
    -v director_name="multi-cpi-bosh" \
    --vars-store "${output_dir}/creds.yml" \
    ~/workspace/bosh-deployment/bosh.yml

  export BOSH_ENVIRONMENT="$( jq -e --raw-output .external_ip "${terraform_output_metadata}" )"
  export BOSH_CLIENT=admin
  export BOSH_CLIENT_SECRET=$( bosh2 int ${output_dir}/creds.yml --path /admin_password )
  export BOSH_CA_CERT=$( bosh2 int ${output_dir}/creds.yml --path /director_ssl/ca )
}

function deployment {
  local az1_env_file=$1
  local az2_env_file=$2
  local stemcell_path=$3
  local release_path=$4

  source "${az1_env_file}"
  local az1_ops="${output_dir}/cpi-config-ops-${ENV_NAME}.yml"
  local az1_cloud_config="${output_dir}/cloud-config-ops-${ENV_NAME}.yml"
  local az1_manifest_ops="${output_dir}/manifest-ops-${ENV_NAME}.yml"

  source "${az2_env_file}"
  local az2_ops="${output_dir}/cpi-config-ops-${ENV_NAME}.yml"
  local az2_cloud_config="${output_dir}/cloud-config-ops-${ENV_NAME}.yml"
  local az2_manifest_ops="${output_dir}/manifest-ops-${ENV_NAME}.yml"

  bosh2 -n update-cpi-config <( bosh2 int -o "${az1_ops}" -o "${az2_ops}" templates/cpi-config.yml )

  bosh2 -n update-cloud-config \
    -o "${az1_cloud_config}" \
    -o "${az2_cloud_config}" \
    -v "env_name=${ENV_NAME}" \
    templates/cloud-config.yml

  bosh2 -n upload-stemcell "${stemcell_path}"

  pushd ~/workspace/bosh-cpi-certification/shared/assets/certification-release
    bosh2 -n create-release --name certification --tarball ${output_dir}/certification-release.tgz --force
  popd
  bosh2 -n upload-release ${output_dir}/certification-release.tgz

  bosh2 deploy -n -d multi-cpi -o "${az1_manifest_ops}" -o "${az2_manifest_ops}" templates/certification-manifest.yml
}

set -e

: ${output_dir:=$1}
destroy=$2
: ${AWS_ACCESS_KEY:?}
: ${AWS_SECRET_KEY:?}
: ${AZ_1:="multi-cpi-az1"}
: ${AZ_2:="multi-cpi-az2"}

if [[ -n "${destroy}" ]]; then
  [[ -d "${output_dir}" ]] || echo "Environment does NOT exist!" && exit 0

  if [[ ! -f "${output_dir}/director-deleted" ]]; then
    source "${output_dir}/${AZ_1}.env"
    terraform_output_metadata="${output_dir}/terraform-metadata-${ENV_NAME}.json"

    export BOSH_ENVIRONMENT="$( jq -e --raw-output .external_ip "${terraform_output_metadata}" )"
    export BOSH_CLIENT=admin
    export BOSH_CLIENT_SECRET=$( bosh2 int ${output_dir}/creds.yml --path /admin_password )
    export BOSH_CA_CERT=$( bosh2 int ${output_dir}/creds.yml --path /director_ssl/ca )

    bosh2 -n -d multi-cpi delete-deployment
    bosh2 -n clean-up --all

    delete_director "${output_dir}/${AZ_1}.env"
  fi

  teardown_iaas "${output_dir}/${AZ_1}.env" "10.0.0.0/16"
  teardown_iaas "${output_dir}/${AZ_2}.env" "10.1.0.0/16"

  rm -rf ${output_dir}
  exit 0
fi

echo "Output directory set to: '${output_dir}/'."
[[ -d "${output_dir}" ]] || mkdir "${output_dir}"

# generate az env files
generate_az_env_file \
  "${AWS_ACCESS_KEY}" \
  "${AWS_SECRET_KEY}" \
  "${AZ_1}" us-east-1 \
  "${AZ_2}" us-west-1

# create multi cpi AZ 1 (contains bosh director)
setup_iaas "${output_dir}/${AZ_1}.env" "10.0.0.0/16"

# create multi cpi AZ 2
setup_iaas "${output_dir}/${AZ_2}.env" "10.1.0.0/16"

# deploy director to AZ 1
deploy_director "${output_dir}/${AZ_1}.env"

# deploy dummy deployment
deployment \
  "${output_dir}/${AZ_1}.env" \
  "${output_dir}/${AZ_2}.env" \
  "https://s3.amazonaws.com/bosh-aws-light-stemcells/light-bosh-stemcell-3421.11-aws-xen-hvm-ubuntu-trusty-go_agent.tgz"
