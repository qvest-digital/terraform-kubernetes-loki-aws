variable "k8s_cluster_type" {
  description = "Can be set to `vanilla` or `eks`. If set to `eks`, the Kubernetes cluster will be assumed to be run on EKS which will make sure that the AWS IAM Service integration works as supposed to."
  type        = string
  default     = "vanilla"
}

variable "k8s_cluster_name" {
  description = "Name of the Kubernetes cluster. This string is used to contruct the AWS IAM permissions and roles. If targeting EKS, the corresponsing managed cluster name must match as well."
  type        = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace to deploy Loki into."
  type        = string
  default     = "default"
}

variable "k8s_pod_annotations" {
  description = "Additional annotations to be added to the Pods."
  type        = map(string)
  default     = {}
}

variable "k8s_pod_container_resources" {
  description = "Resource requests/limits to set."
  type = object({
    limits = object({
      cpu    = string
      memory = string
    })
    requests = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    limits = {
      cpu    = "2000m"
      memory = "1024Mi"
    }
    requests = {
      cpu    = "1000m"
      memory = "256Mi"
    }
  }
}

variable "k8s_replicas" {
  description = "Amount of Loki replicas to spawn."
  type        = number
  default     = 1
}

variable "k8s_priority_class_name" {
  description = "Name of the priority class to be assigned to Pods."
  type        = string
  default     = null
}

variable "k8s_node_selector" {
  description = "Node selector to make sure that Loki only runs on specific Nodes."
  type        = map(string)
  default     = {}
}

variable "k8s_node_tolerations" {
  description = "Additional tolerations that are required to run on selected specific Nodes."
  type = list(object({
    effect   = string
    key      = string
    operator = string
    value    = string
  }))
  default = []
}

variable "aws_iam_path_prefix" {
  description = "Prefix to be used for all AWS IAM objects."
  type        = string
  default     = "/"
}

variable "aws_resource_name_prefix" {
  description = "A string to prefix any AWS resources created. This does not apply to K8s resources"
  type        = string
  default     = "k8s-"
}

variable "aws_tags" {
  description = "Common AWS tags to be applied to all AWS objects being created."
  type        = map(string)
  default     = {}
}

variable "loki_version" {
  description = "The Loki version to use. See https://github.com/grafana/loki/releases for available versions"
  type        = string
  default     = "1.5.0"
}

variable "loki_ingress_host" {
  description = "Loki ingress hostname"
  type        = string
  default     = "loki"
}
