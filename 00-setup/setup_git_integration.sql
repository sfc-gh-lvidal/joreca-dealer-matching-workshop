-- ----------------------------------------------------------------------
-- Block 0 (admin, run ONCE) - API integration for Git workspaces
-- Lets every developer create a Snowsight workspace from this GitHub repo:
--   Projects > Workspaces > From Git repository
-- ----------------------------------------------------------------------

-- CREATE API INTEGRATION is an account-level privilege, usually held by ACCOUNTADMIN only.
USE ROLE ACCOUNTADMIN;

-- git_https_api = Snowflake talks to a Git provider over HTTPS.
-- API_ALLOWED_PREFIXES restricts the integration to this GitHub account only.
-- The repo is public: no secret is needed (ALLOWED_AUTHENTICATION_SECRETS omitted).
-- Consequence: workspaces can PULL but cannot commit / push to this repo.
-- To push to your own private repo later, add a SECRET (GitHub PAT) or configure OAuth2.
CREATE OR REPLACE API INTEGRATION GITHUB_WORKSHOP_API
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-lvidal')
    ENABLED = TRUE
    COMMENT = 'Joreca workshop - read-only access to the public workshop repo';

-- The developers' role needs USAGE to see the integration in the Snowsight dialog.
-- Replace SYSADMIN with the role the developers select in Snowsight (user menu > Switch role).
GRANT USAGE ON INTEGRATION GITHUB_WORKSHOP_API TO ROLE SYSADMIN;

SHOW API INTEGRATIONS LIKE 'GITHUB_WORKSHOP_API';

-- Cleanup after the workshop:
-- DROP API INTEGRATION IF EXISTS GITHUB_WORKSHOP_API;
