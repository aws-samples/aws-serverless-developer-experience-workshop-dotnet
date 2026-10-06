# SAM and Terraform parity contract

This document defines how the Terraform implementation mirrors the AWS SAM implementation. It is the review contract for translating future SAM changes into Terraform without introducing silent drift.

## One-way sync model

The SAM branches are authoritative. Infrastructure changes flow one way from SAM to the Terraform mirror:

```text
SAM develop ──translate and verify──> Terraform development mirror
SAM main    ──translate and verify──> Terraform release mirror
```

Do not merge Terraform infrastructure changes back into the SAM branches as a parity mechanism. Make the source change in SAM first, then translate it into the owning Terraform root and verify the participant-visible result.

| SAM source branch | Terraform mirror | Current contract |
| --- | --- | --- |
| `develop` | `tf-dev` | `tf-dev` is the current development mirror and receives translated changes from `develop`. |
| `main` | `tf-main` when that release mirror is established | Promote only changes already translated and verified against the corresponding SAM behavior. |

This contract does not retire or rename `tf-dev`. If maintainers later introduce `tf-develop` or change the release branch arrangement, update this table as part of that decision rather than inferring a branch lifecycle here.

For every difference found during a sync, classify it as one of the following:

1. **Must match:** translate the SAM behavior into Terraform.
2. **Accepted divergence:** confirm that the difference is listed in the register below and still has the stated rationale.
3. **Drift:** stop the sync and correct or explicitly review the unregistered difference.

## Terraform directory map

Terraform deployment state is split across 15 independent roots. Each root has its own backend key and committed `.terraform.lock.hcl`. The deployment phase is part of the contract because later roots consume resources and SSM parameters created by earlier roots.

| Phase | Owner | Terraform root | SAM responsibility mirrored |
| --- | --- | --- | --- |
| Shared | Shared | `Unicorn.Shared/Infrastructure/api-gateway-account` | Account/Region API Gateway CloudWatch logging configuration |
| Shared | Shared | `Unicorn.Shared/Infrastructure/namespaces` | Global Contracts, Approvals, and Web namespace parameters |
| Shared | Shared | `Unicorn.Shared/Infrastructure/uniprop-images` | Stage image bucket and initialization resources |
| Domains | Contracts | `Unicorn.Contracts/Infrastructure/domain` | Contracts event bus, policies, forwarding role, logging, registry, and SSM contracts |
| Domains | Approvals | `Unicorn.Approvals/Infrastructure/domain` | Approvals event bus, policies, forwarding role, logging, registry, and SSM contracts |
| Domains | Web | `Unicorn.Web/Infrastructure/domain` | Web event bus, policies, forwarding role, logging, registry, and SSM contracts |
| Schemas | Contracts | `Unicorn.Contracts/Infrastructure/schema-registry/ContractStatusChanged` | `ContractStatusChanged` schema |
| Schemas | Approvals | `Unicorn.Approvals/Infrastructure/schema-registry/PublicationEvaluationCompleted` | `PublicationEvaluationCompleted` schema |
| Schemas | Web | `Unicorn.Web/Infrastructure/schema-registry/PublicationApprovalRequested` | `PublicationApprovalRequested` schema |
| Workloads | Contracts | `Unicorn.Contracts/Infrastructure/contracts-service` | Contracts API, queue, Lambda, DynamoDB, pipe, IAM, and logs |
| Workloads | Approvals | `Unicorn.Approvals/Infrastructure/approvals-service` | Approval Lambdas, DynamoDB, Step Functions, IAM, queues, and logs |
| Workloads | Web | `Unicorn.Web/Infrastructure/web-service` | Web API, Lambdas, DynamoDB, queues, IAM, and logs |
| Subscriptions | Approvals | `Unicorn.Approvals/Infrastructure/subscriptions/unicorn-contracts` | Consumer-owned Contracts-to-Approvals forwarding rule |
| Subscriptions | Approvals | `Unicorn.Approvals/Infrastructure/subscriptions/unicorn-web` | Consumer-owned Web-to-Approvals forwarding rule |
| Subscriptions | Web | `Unicorn.Web/Infrastructure/subscriptions/approvals` | Consumer-owned Approvals-to-Web forwarding rule |

Contracts and Web render their REST API definitions from `api.yaml.tpl`. Approvals renders its Step Functions definition from `PropertyApproval.asl.json`. These files are inputs to Terraform resources, not separate SAM deployment stacks.

Roots exchange names and ARNs through SSM Parameter Store, not Terraform remote state. The contract includes the global `/uni-prop/Unicorn{Service}Namespace` parameters and the stage-scoped `/uni-prop/${stage}/` parameters for event bus names and ARNs, schema registry names, event forwarding role ARNs, and `ImagesBucket`.

## Must-match participant-visible surfaces

Unless the accepted-divergence register says otherwise, the Terraform deployment must match SAM at the same stage on these surfaces:

- AWS resource names that participants, scripts, tests, or integrations observe, including APIs, stages, queues, functions, tables, event buses, rules, state machines, schema registries, and log groups.
- SSM parameter names and values, including global namespaces and every stage-scoped event bus, registry, image bucket, and EventBridge forwarding-role contract.
- Terraform output names and values that correspond to SAM stack outputs, including API endpoints, function ARNs, event bus identifiers, and registry identifiers.
- Registered event schema names, property names, casing, required fields, and schema content.
- Event source and detail-type values, EventBridge filters, input transformations, targets, retry/dead-letter behavior, and cross-service event flow.
- API paths, methods, CORS behavior, request schemas and validators, service integrations, Lambda integrations, responses, and endpoint output values.
- Lambda runtime behavior, environment values, trigger mappings, timeout/memory settings, observability settings, and effective IAM permissions.
- DynamoDB keys, indexes, stream behavior, billing behavior, and table names, apart from the production protections registered below.
- Makefile participant verbs and stage semantics: `init`, `plan`, `deploy`, `build`, `local-invoke`, `test`, `lint`, `clean`, and reverse-order `delete`, plus component-specific variants.
- The logical directory-to-resource ownership mapping, even though Terraform splits state into the 15 roots above.

The current logging behavior is also must-match:

- The Contracts, Web, and Approvals service catch-all EventBridge rules are `ENABLED` for `local`, `dev`, and `prod`. They filter on the current account and expected service source; the Approvals rule accepts forwarded Contracts and Web sources.
- Catch-all log retention is 3 days for `local` and `dev`, and 14 days for `prod`.
- The Approvals Step Functions workflow logs at `ALL`, includes execution data in every stage, and enables X-Ray tracing.
- Contracts and Web API stages emit structured access logs and enable X-Ray. Wildcard method execution logging uses `INFO` outside production and `ERROR` in production.
- Domain event buses use full-detail EventBridge logging, with `INFO` outside production and `ERROR` in production.

A difference on one of these surfaces that is not in the register is drift.

## Accepted-divergence register

| Surface | SAM behavior | Terraform behavior | Rationale |
| --- | --- | --- | --- |
| Explicit resource, IAM role, and log-group names | CloudFormation and SAM can generate physical names and implicit execution roles or log groups. | Terraform declares stable participant-visible names, explicit IAM roles and policies, and static Lambda log-group names created before the functions use them. | Explicit ownership avoids generated-name drift, supports cross-root references, and prevents first-invocation log-group races while preserving required external names. |
| SSM parameters instead of CloudFormation exports | SAM stacks can compose resources through CloudFormation outputs and exports. | Independent Terraform roots publish and consume the equivalent operational names and ARNs through SSM; they do not read another root's state. | SSM keeps the existing cross-IaC contract, avoids remote-state coupling, and lets roots retain separate lifecycles. SSM parameter names and values still must match. |
| Terraform state backend | CloudFormation owns SAM stack state. | Terraform uses a versioned S3 state bucket, S3-native `.tflock` objects, and a separate backend key for every root and stage where applicable. | Terraform requires durable state and locking. Separate keys limit blast radius and prevent roots from co-owning resources. |
| Production DynamoDB point-in-time recovery and deletion protection | The SAM workshop baseline does not add Terraform lifecycle protections. | Terraform enables point-in-time recovery and deletion protection for service tables in `prod`. | These controls protect production data from Terraform lifecycle and destroy mistakes without changing table APIs or participant workflows. |
| S3 hardening | The SAM workshop baseline does not express every Terraform-specific bucket control. | Terraform declares public-access blocking and AES256 server-side encryption for the shared image bucket, with versioning enabled in `prod` and suspended for local/development ergonomics. A state bucket created by `common.mk` also receives public-access blocking, AES256 encryption, and versioning. | No-cost safeguards reduce accidental exposure and protect Terraform state. Stage-aware image versioning preserves workshop cost and iteration behavior. |
| API Gateway account singleton | SAM service stacks do not use a separate Terraform state root for the account-level API Gateway logging role. | `Unicorn.Shared/Infrastructure/api-gateway-account` is the sole account/Region owner of `aws_api_gateway_account`; service method settings depend operationally on it. Aggregate deletion preserves this root. | The AWS setting is an account/Region singleton. One owner prevents replacement conflicts and accidental removal by a service stack. |
| Deterministic Lambda packaging | SAM performs its normal build and packaging workflow. | Service Makefiles create deterministic ZIP files through `scripts/package_dotnet_lambda.py`; package freshness checks reject missing or stale artifacts with a `make package-service` remedy. Terraform exposes `sam_metadata_*` resources so SAM can build and invoke Terraform-defined functions locally. | Reproducible archives produce stable hashes, and fail-fast freshness checks prevent stale code deployments while retaining SAM local-development support. |
| Shared infrastructure layout | SAM represents shared image infrastructure in `uni-prop-images.yaml` alongside its other deployment templates. | Terraform uses the independent `Unicorn.Shared/Infrastructure/uniprop-images` root, alongside separate `namespaces` and `api-gateway-account` roots. | Renaming a state-bearing root would add migration risk without changing deployed behavior. The explicit split reflects separate lifecycle and singleton ownership. |

## Root orchestration contract

From the repository root, `make deploy-all STAGE=<local|dev|prod>` applies the roots in five phases:

1. Ensure the shared state backend exists.
2. Apply the API Gateway account singleton, global namespaces, and the selected stage's image root.
3. Apply the Contracts, Approvals, and Web domain roots.
4. Apply all schema roots, then all workload roots.
5. Apply the three consumer-owned subscription roots.

`make delete-all STAGE=<local|dev|prod> CONFIRM_ACCOUNT_GLOBAL=DESTROY` runs the stage-scoped operations in reverse dependency order, then removes the account-global namespace parameters used by every stage. The independent confirmation token is required because namespace removal can affect local, development, and production deployments. The command preserves the API Gateway account singleton and Terraform state backend. Direct Shared namespace deletion requires the same token. Other namespace/component Makefile targets remain available for narrower work. Shared `init` leaves `uniprop-images` configured with the safe `local` backend key; stage-specific work must use the matching stage target.

## Future SAM-to-Terraform sync checklist

- [ ] Start from the intended authoritative SAM branch (`develop` for current development work or `main` for a release sync) and record the source commit.
- [ ] Sync application and documentation changes first, preserving Terraform deployment ownership and the build-only SAM configuration. Do not restore deleted SAM deployment resources.
- [ ] Preserve Web's non-parallel SAM build setting so projects sharing the `Common` output do not publish concurrently.
- [ ] Inventory every changed SAM resource, output, API definition, event schema, ASL definition, Make target, and participant workflow.
- [ ] Map each infrastructure change to one or more of the 15 Terraform roots. Add no new root without updating the validator, directory map, deployment order, backend ownership, and review contract.
- [ ] Compare every must-match surface above, including names, outputs, SSM values, schemas, APIs, event flows, IAM effects, catch-all rules, and logging behavior.
- [ ] Preserve the SSM contract and five-phase dependency order. Treat a parameter rename or removal as a cross-root and cross-IaC breaking change.
- [ ] Render REST API changes through the owning `api.yaml.tpl` and workflow changes through `PropertyApproval.asl.json`; do not recreate deleted SAM deployment templates in the Terraform mirror.
- [ ] Classify every observed difference as must-match, an existing accepted divergence, or drift. Review and document any proposed new divergence before implementation.
- [ ] Package changed Lambda functions through the owning service Makefile and confirm the deterministic ZIP freshness guard passes.
- [ ] Run `python3 scripts/validate_infrastructure.py --checkov` from the repository root. It must validate the exact 15-root inventory and honor only the 21 intentional exceptions in `.checkov.yml`.
- [ ] Run link/content checks and `git diff --check` for documentation and repository consistency.
- [ ] Deploy the `dev` stage through `make deploy-all STAGE=dev`, then run the existing integration tests.
- [ ] Verify Contracts-to-Approvals event flow, Approvals-to-Web flow, registered schemas, API outputs, and `/request_approval` validation against the SAM deployment before promotion.
- [ ] Review the accepted-divergence register for continued validity and update the source commit/reference used for the next sync.
