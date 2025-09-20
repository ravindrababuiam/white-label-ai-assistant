{{/*
Expand the name of the chart.
*/}}
{{- define "customer-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "customer-stack.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "customer-stack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "customer-stack.labels" -}}
helm.sh/chart: {{ include "customer-stack.chart" . }}
{{ include "customer-stack.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: white-label-ai-assistant
customer: {{ .Values.global.customerName }}
environment: {{ .Values.global.environment }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "customer-stack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "customer-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Open WebUI labels
*/}}
{{- define "open-webui.labels" -}}
{{ include "customer-stack.labels" . }}
app.kubernetes.io/component: open-webui
{{- end }}

{{/*
Open WebUI selector labels
*/}}
{{- define "open-webui.selectorLabels" -}}
{{ include "customer-stack.selectorLabels" . }}
app.kubernetes.io/component: open-webui
{{- end }}

{{/*
Ollama labels
*/}}
{{- define "ollama.labels" -}}
{{ include "customer-stack.labels" . }}
app.kubernetes.io/component: ollama
{{- end }}

{{/*
Ollama selector labels
*/}}
{{- define "ollama.selectorLabels" -}}
{{ include "customer-stack.selectorLabels" . }}
app.kubernetes.io/component: ollama
{{- end }}

{{/*
Qdrant labels
*/}}
{{- define "qdrant.labels" -}}
{{ include "customer-stack.labels" . }}
app.kubernetes.io/component: qdrant
{{- end }}

{{/*
Qdrant selector labels
*/}}
{{- define "qdrant.selectorLabels" -}}
{{ include "customer-stack.selectorLabels" . }}
app.kubernetes.io/component: qdrant
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "customer-stack.serviceAccountName" -}}
{{- if .Values.aws.serviceAccount.create }}
{{- default (include "customer-stack.fullname" .) .Values.aws.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.aws.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Generate AWS S3 bucket name for documents
*/}}
{{- define "customer-stack.s3.documentsBucket" -}}
{{- if .Values.aws.s3.buckets.documents }}
{{- .Values.aws.s3.buckets.documents }}
{{- else }}
{{- printf "%s-documents-%s" .Values.global.customerName (randAlphaNum 8 | lower) }}
{{- end }}
{{- end }}

{{/*
Generate AWS S3 bucket name for data
*/}}
{{- define "customer-stack.s3.dataBucket" -}}
{{- if .Values.aws.s3.buckets.data }}
{{- .Values.aws.s3.buckets.data }}
{{- else }}
{{- printf "%s-data-%s" .Values.global.customerName (randAlphaNum 8 | lower) }}
{{- end }}
{{- end }}

{{/*
Generate secret key for Open WebUI
*/}}
{{- define "customer-stack.secretKey" -}}
{{- if .Values.secrets.openWebUI.secretKey }}
{{- .Values.secrets.openWebUI.secretKey }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
Common AWS environment variables
*/}}
{{- define "customer-stack.awsEnvVars" -}}
- name: AWS_REGION
  value: {{ .Values.global.aws.region | quote }}
- name: AWS_DEFAULT_REGION
  value: {{ .Values.global.aws.region | quote }}
{{- if .Values.global.aws.accountId }}
- name: AWS_ACCOUNT_ID
  value: {{ .Values.global.aws.accountId | quote }}
{{- end }}
{{- end }}

{{/*
Common security context
*/}}
{{- define "customer-stack.securityContext" -}}
runAsNonRoot: {{ .Values.global.securityContext.runAsNonRoot | default true }}
runAsUser: {{ .Values.global.securityContext.runAsUser | default 1000 }}
fsGroup: {{ .Values.global.securityContext.fsGroup | default 2000 }}
{{- end }}

{{/*
Common pod security context
*/}}
{{- define "customer-stack.podSecurityContext" -}}
runAsNonRoot: {{ .Values.global.securityContext.runAsNonRoot | default true }}
runAsUser: {{ .Values.global.securityContext.runAsUser | default 1000 }}
{{- end }}

{{/*
Resource limits helper
*/}}
{{- define "customer-stack.resources" -}}
{{- if . }}
resources:
  {{- if .requests }}
  requests:
    {{- if .requests.memory }}
    memory: {{ .requests.memory }}
    {{- end }}
    {{- if .requests.cpu }}
    cpu: {{ .requests.cpu }}
    {{- end }}
  {{- end }}
  {{- if .limits }}
  limits:
    {{- if .limits.memory }}
    memory: {{ .limits.memory }}
    {{- end }}
    {{- if .limits.cpu }}
    cpu: {{ .limits.cpu }}
    {{- end }}
    {{- if .limits.gpu }}
    nvidia.com/gpu: {{ .limits.gpu }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}