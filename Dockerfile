# Build stage for the adv image (gitlab.adv.team ci/images/mcp-atlassian).
# myci builds this Dockerfile and copies only /app/.venv into its runtime base,
# registry.adv.team/images/ci-images-python/python-3.13, so both images must
# provide the same /usr/bin/python3.13.
FROM registry.adv.team/images/ci-images-python/python-tools-3.13

# Install the project into `/app`
WORKDIR /app

# Enable bytecode compilation
ENV UV_COMPILE_BYTECODE=1

# Copy from the cache instead of linking since it's a mounted volume
ENV UV_LINK_MODE=copy

# Build the venv on the system Python shared with the runtime base image
ENV UV_PYTHON=/usr/bin/python3.13
ENV UV_PYTHON_DOWNLOADS=never

# The build context has no git history, so set the version explicitly
ARG VERSION=0.23.1+adv
ENV UV_DYNAMIC_VERSIONING_BYPASS=${VERSION}

# Install the project's dependencies using the lockfile
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    uv sync --frozen --extra wpad --no-install-project --no-dev --no-editable

# Then, copy the rest of the project source code and install it
COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --extra wpad --no-dev --no-editable

# Remove unnecessary files from the virtual environment
RUN find /app/.venv -name '__pycache__' -type d -exec rm -rf {} + && \
    find /app/.venv -name '*.pyc' -delete && \
    find /app/.venv -name '*.pyo' -delete && \
    echo "Cleaned up .venv"

# Fail the build if the adv fixes or the FastMCP proxy setting are missing.
# (myci treats any line starting with "from" as FROM, so keep imports inline.)
RUN /app/.venv/bin/python -c "import fastmcp; assert hasattr(fastmcp.settings, 'ssrf_trust_proxy')" \
 && /app/.venv/bin/python -c "import mcp_atlassian.jira.client as c; assert hasattr(c.JiraClient, '_check_projects_filter')" \
 && /app/.venv/bin/python -c "import mcp_atlassian.jira.search as s; assert hasattr(s.SearchMixin, '_get_accessible_config_projects_filter')"
