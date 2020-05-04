# Terraform module: Loki (on AWS Cloud Infrastructure)

This Terraform module can be used to install the [Loki](https://github.com/grafana/loki/)
into a Kubernetes cluster which will utilize AWS (S3 and DynamoDB) to store logs.

## Examples

### Default deployment

To deploy Loki into an existing EKS cluster, the following snippet might be used.

```hcl

module "loki" {
  source           = "iplabs/loki-aws/kubernetes"
  version          = "1.0.0"
  k8s_cluster_type = "eks"
  k8s_cluster_name = "mycluster"
}
```
