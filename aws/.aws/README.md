# AWS Configuration

Uses AWS's `credential_process` to fetch credentials from 1Password on demand, avoiding plaintext credential storage.

## How It Works

1. **AWS Config**: The `~/.aws/config` file uses `credential_process` to call an external program for credentials
2. **1Password Vault**: AWS credentials are stored securely in 1Password
3. **op CLI**: The 1Password CLI (`op`) fetches credentials when needed
4. **aws-1password Helper**: A bash script that translates AWS profile names to 1Password entries and formats the response

## Prerequisites

- 1Password CLI (`op`) installed and configured
- AWS CLI installed

## 1Password Vault Setup

Create the following entries in your 1Password CLI vault:

1. **AWSCredsUsernamenickromney** (for default profile):
   - `ACCESS_KEY`: Your AWS access key ID
   - `SECRET_KEY`: Your AWS secret access key

2. **AWSCredsUsernameTFCLI** (for tfcli profile):
   - `ACCESS_KEY`: Your Terraform CLI user access key ID
   - `SECRET_KEY`: Your Terraform CLI user secret access key

## Configuration Setup

1. Copy the example configuration:

   ```bash
   cp config.example config
   ```

2. Update the account ID in `role_arn` (replace `123456789` with your actual AWS account ID)

3. Ensure the helper script is executable:

   ```bash
   chmod +x aws-1password
   ```

## How credential_process Works

Each profile in `config` includes:

```ini
credential_process = /Users/[username]/.aws/aws-1password --username [profile]
```

When you run an AWS command, the CLI:

1. Calls `aws-1password` with the specified username
2. The script maps the username to a 1Password entry
3. Fetches credentials from 1Password using `op`
4. Returns them in the JSON format AWS expects

## Usage

```bash
# Default profile
aws s3 ls

# Specific profile
aws s3 ls --profile UserTFCLI

# AssumeRole via Deployments profile
aws s3 ls --profile Deployments
```

## Adding New Profiles

1. Add the profile to `config` with appropriate `credential_process` line
2. Create corresponding 1Password entry
3. Update `get_op_entry()` function in `aws-1password` to map the new profile

## Security

- Never commit `config` (only `config.example`)
- Credentials are fetched from 1Password on each AWS CLI invocation
- No credentials are stored on disk
