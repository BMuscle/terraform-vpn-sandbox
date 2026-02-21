env ?= ""

init: guard-env fmt
	terraform init -backend-config=backends/${env}.tfbackend -reconfigure

plan: tf-plan

apply: tf-apply tf-refresh

fmt:
	terraform fmt -check -recursive

validate:
	terraform validate

tf-%: init validate
	terraform ${*} -var-file=vars/${env}.tfvars

guard-%:
	@ if [ "${${*}}" = "" ]; then \
		echo "Environment variable '$*' not set"; \
		exit 1; \
	fi
