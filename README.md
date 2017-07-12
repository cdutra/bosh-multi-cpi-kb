# bosh-multi-cpi-kb

### Deploy multi cpi on AWS

```
./deploy-multi-cpi.sh output-dir
```

To destroy the whole environment:
```
./deploy-multi-cpi.sh output-dir destroy
```

# TODO

### Upload heavy stemcells

Uploading heavy stemcells fails:
```
bosh2 upload-stemcell bosh-stemcell-3421.9-aws-xen-hvm-ubuntu-trusty-go_agent.tgz
Using environment '34.226.175.131' as client 'admin'

###################################################### 100.00% 671.95 KB/s 9m16s
Task 8

10:40:51 | Update stemcell: Extracting stemcell archive (00:00:03)
10:40:54 | Update stemcell: Verifying stemcell manifest (00:00:00)
10:40:58 | Update stemcell: Checking if this stemcell already exists (cpi: multi-cpi-az1) (00:00:00)
10:40:58 | Update stemcell: Uploading stemcell bosh-aws-xen-hvm-ubuntu-trusty-go_agent/3421.9 to the cloud (cpi: multi-cpi-az1) (00:04:23)
10:45:21 | Update stemcell: Save stemcell bosh-aws-xen-hvm-ubuntu-trusty-go_agent/3421.9 (ami-c30408d5) (cpi: multi-cpi-az1) (00:00:00)
10:45:26 | Update stemcell: Checking if this stemcell already exists (cpi: multi-cpi-az2) (00:00:00)
10:45:26 | Update stemcell: Uploading stemcell bosh-aws-xen-hvm-ubuntu-trusty-go_agent/3421.9 to the cloud (cpi: multi-cpi-az2) (00:00:04)
            L Error: CPI error 'Bosh::Clouds::CloudError' with message 'Could not locate the current VM with id 'i-08ebf9dfbd47fba1f'.Ensure that the current VM is located in the same region as configured in the manifest.' in 'create_stemcell' CPI method

10:45:30 | Error: CPI error 'Bosh::Clouds::CloudError' with message 'Could not locate the current VM with id 'i-08ebf9dfbd47fba1f'.Ensure that the current VM is located in the same region as configured in the manifest.' in 'create_stemcell' CPI method

Started  Wed Jul 12 10:40:51 UTC 2017
Finished Wed Jul 12 10:45:30 UTC 2017
Duration 00:04:39

Task 8 error

Uploading stemcell file:
  Expected task '8' to succeed but state is 'error'

Exit code 1
```

This happens because AWS CPI performs the following steps to create a stemcell:
1. [Lookup for BOSH director instance](https://github.com/cloudfoundry-incubator/bosh-aws-cpi-release/blob/28c682a500f528c1bb1dac17bbf517c073397d56/src/bosh_aws_cpi/lib/cloud/aws/cloud.rb#L641) on non-default region.
2. Create disk
3. Attach disk to BOSH Director VM
4. Take snapshot of attached disk
5. Create image from snapshot

### Deleting stemcells

Deleting light stemcells fails:
```
bosh2 clean-up --all
Using environment '34.226.175.131' as client 'admin'

Continue? [yN]: y

Task 12

10:59:03 | Deleting stemcells: bosh-aws-xen-hvm-ubuntu-trusty-go_agent/3421.11 (00:00:09) (00:00:14)
            L Error: Attempt to delete object did not result in a single row modification (Rows Deleted: 0, SQL: DELETE FROM "stemcells" WHERE ("id" = 4))

10:59:17 | Error: Attempt to delete object did not result in a single row modification (Rows Deleted: 0, SQL: DELETE FROM "stemcells" WHERE ("id" = 4))

Started  Wed Jul 12 10:59:03 UTC 2017
Finished Wed Jul 12 10:59:17 UTC 2017
Duration 00:00:14

Task 12 error

Cleaning up resources:
  Expected task '12' to succeed but state is 'error'

Exit code 1
```

0. Use https://github.com/dpb587/openvpn-bosh-release to setup vpn between vpcs in different regions
0. Deploy 3rd cpi to gcp
