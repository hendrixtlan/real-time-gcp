#!/usr/bin/env bash
# =============================================================================
# deploy.sh — orden completo de despliegue del stack CDC-MX
#
# Pre-requisitos:
#   - gcloud autenticado con permisos de Owner o equivalente
#   - terraform >= 1.5
#   - docker
#   - Oracle ya configurado (oracle/setup.sql ejecutado por DBA)
#   - Conectividad GCP↔Oracle establecida (Interconnect/VPN)
#   - terraform/envs/prod/terraform.tfvars creado a partir del .example
#
# Uso:
#   ./scripts/deploy.sh [stage]
# Stages:
#   1-bootstrap   APIs + state bucket (correr 1 vez)
#   2-images      Build y push de imágenes (ARCO, reconciliation, dataflow)
#   3-infra       terraform apply (toda la infra)
#   4-schemas     Aplicar SQLs en AlloyDB y BigQuery
#   5-streams     Iniciar Datastream (esto activa CDC)
#   all           Todo en orden
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform/envs/prod"
STAGE="${1:-all}"

# Cargar config desde tfvars (sólo lo que necesitamos en bash)
get_tfvar() {
    grep -E "^\s*${1}\s*=" "$TF_DIR/terraform.tfvars" | sed -E 's/.*=\s*"?([^"]+)"?\s*$/\1/' | tr -d '"'
}

PROJECT_ID="$(get_tfvar project_id)"
REGION="$(get_tfvar region)"
PREFIX="$(get_tfvar prefix)"

if [[ -z "$PROJECT_ID" ]]; then
    echo "ERROR: project_id no encontrado en $TF_DIR/terraform.tfvars" >&2
    exit 1
fi

REPO="${REGION}-docker.pkg.dev/${PROJECT_ID}/${PREFIX}"

log() { echo -e "\n\033[1;36m== $* ==\033[0m"; }

# =============================================================================
stage_bootstrap() {
    log "Stage 1: Bootstrap (APIs + state bucket)"
    gcloud config set project "$PROJECT_ID"
    gcloud services enable \
        compute.googleapis.com \
        cloudresourcemanager.googleapis.com \
        iam.googleapis.com \
        storage.googleapis.com \
        artifactregistry.googleapis.com \
        cloudbuild.googleapis.com \
        --project="$PROJECT_ID"

    BUCKET="gs://${PROJECT_ID}-tfstate"
    if ! gsutil ls "$BUCKET" >/dev/null 2>&1; then
        gsutil mb -l "$REGION" -b on "$BUCKET"
        gsutil versioning set on "$BUCKET"
        echo "Bucket de tfstate creado: $BUCKET"
    fi
}

# =============================================================================
stage_images() {
    log "Stage 2: Build y push de imágenes"

    # Configurar Docker para Artifact Registry
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

    # Crear repo si no existe
    gcloud artifacts repositories describe "$PREFIX" --location="$REGION" >/dev/null 2>&1 || \
        gcloud artifacts repositories create "$PREFIX" \
            --repository-format=docker --location="$REGION"

    log "Build ARCO"
    docker build -t "${REPO}/arco:latest" "$ROOT_DIR/services/arco"
    docker push "${REPO}/arco:latest"

    log "Build reconciliation"
    docker build -t "${REPO}/reconciliation:latest" "$ROOT_DIR/services/reconciliation"
    docker push "${REPO}/reconciliation:latest"

    log "Build y push Dataflow flex template"
    bash "$ROOT_DIR/dataflow/serving/build_and_deploy.sh" \
        "$PROJECT_ID" "$REGION" "$PREFIX"

    echo
    echo "Imágenes publicadas:"
    echo "  ${REPO}/arco:latest"
    echo "  ${REPO}/reconciliation:latest"
    echo "  Dataflow template: gs://${PROJECT_ID}-${PREFIX}-dataflow-templates/serving.json"
}

# =============================================================================
stage_infra() {
    log "Stage 3: terraform apply"
    cd "$TF_DIR"
    terraform init
    terraform plan -out=tfplan
    read -rp "¿Aplicar? (yes/no): " confirm
    [[ "$confirm" == "yes" ]] || { echo "Cancelado"; exit 0; }
    terraform apply tfplan
    rm -f tfplan
    cd "$ROOT_DIR"
}

# =============================================================================
stage_schemas() {
    log "Stage 4: Aplicar schemas"

    # AlloyDB
    log "Aplicando SQLs en AlloyDB"
    ALLOYDB_IP="$(cd "$TF_DIR" && terraform output -raw alloydb_primary_ip)"
    ALLOYDB_PASS="$(get_tfvar alloydb_initial_password)"
    export PGPASSWORD="$ALLOYDB_PASS"

    # Necesita conectividad — desde Cloud Shell o jump host con acceso a la VPC
    psql "host=$ALLOYDB_IP port=5432 user=postgres dbname=postgres" -c "CREATE DATABASE cdc_mx;" || true
    psql "host=$ALLOYDB_IP port=5432 user=postgres dbname=cdc_mx" -f "$ROOT_DIR/alloydb/01_schema.sql"
    psql "host=$ALLOYDB_IP port=5432 user=postgres dbname=cdc_mx" -f "$ROOT_DIR/alloydb/02_compliance.sql"
    psql "host=$ALLOYDB_IP port=5432 user=postgres dbname=cdc_mx" -f "$ROOT_DIR/alloydb/03_purge_jobs.sql"

    # Crear usuarios y assignar passwords (en producción usar Secret Manager)
    psql "host=$ALLOYDB_IP port=5432 user=postgres dbname=cdc_mx" <<EOF
CREATE USER cdc_writer    WITH LOGIN PASSWORD '$(openssl rand -base64 24)' IN ROLE cdc_writer;
CREATE USER app_reader    WITH LOGIN PASSWORD '$(openssl rand -base64 24)' IN ROLE app_reader;
CREATE USER arco_service  WITH LOGIN PASSWORD '$(openssl rand -base64 24)' IN ROLE arco_service;
EOF

    # Actualizar el secret de connection string
    CONN="host=$ALLOYDB_IP port=5432 dbname=cdc_mx user=cdc_writer"
    echo -n "$CONN" | gcloud secrets versions add "${PREFIX}-alloydb-writer-conn" \
        --data-file=- --project="$PROJECT_ID"

    unset PGPASSWORD

    # BigQuery
    log "Aplicando SQLs en BigQuery"
    bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false \
        --parameter="project_id:STRING:$PROJECT_ID" \
        < <(sed "s/\${PREFIX}/${PREFIX}/g" "$ROOT_DIR/bigquery/01_setup.sql")
    bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false \
        < <(sed "s/\${PREFIX}/${PREFIX}/g" "$ROOT_DIR/bigquery/02_views.sql")
}

# =============================================================================
stage_streams() {
    log "Stage 5: Iniciar streams Datastream"
    BQ_STREAM="$(cd "$TF_DIR" && terraform output -raw datastream_bq_stream_id)"
    GCS_STREAM="$(cd "$TF_DIR" && terraform output -raw datastream_gcs_stream_id)"

    gcloud datastream streams update "$BQ_STREAM" \
        --location="$REGION" --update-mask=state --state=RUNNING --project="$PROJECT_ID"
    gcloud datastream streams update "$GCS_STREAM" \
        --location="$REGION" --update-mask=state --state=RUNNING --project="$PROJECT_ID"

    echo "Streams iniciados. Lag esperado:"
    echo "  Datastream → BigQuery: 5-30s"
    echo "  Datastream → GCS → Dataflow → AlloyDB: 1-3s"
    echo
    echo "Monitorea con: bash scripts/verify.sh"
}

# =============================================================================
case "$STAGE" in
    1-bootstrap)  stage_bootstrap ;;
    2-images)     stage_images ;;
    3-infra)      stage_infra ;;
    4-schemas)    stage_schemas ;;
    5-streams)    stage_streams ;;
    all)
        stage_bootstrap
        stage_images
        stage_infra
        stage_schemas
        stage_streams
        ;;
    *)
        echo "Stage desconocido: $STAGE"
        echo "Opciones: 1-bootstrap | 2-images | 3-infra | 4-schemas | 5-streams | all"
        exit 1
        ;;
esac

log "Listo: $STAGE"
