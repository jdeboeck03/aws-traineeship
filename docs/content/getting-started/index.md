# Getting Started

## AWS Console

Axxes accounts are managed through Active Directory. Open the AWS access portal at
<https://axxes.awsapps.com/start/#/> and log in with your Axxes AD credentials.
Select the **traineeship-2026** account and open the console from there.

### Picking a region

In the top right corner of the AWS console, select **eu-west-1 (Ireland)** from the region dropdown.
All resources in this traineeship will be created in this region.

## AWS CLI

### Installation

Install the AWS CLI v2 by following the [official instructions](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
for your operating system.

Verify the installation:

```shell
aws --version
```

### Configuring SSO

Run the interactive configuration wizard:

```shell
aws configure sso
```

Fill in the prompts as follows:

```
SSO session name: axxes
SSO start URL:    https://axxes.awsapps.com/start/#/
SSO region:       eu-west-1
```

A browser window will open — log in with your Axxes AD credentials. The CLI will then show you the
accounts and roles you have access to. Select **traineeship-2026** and **AdministratorAccess**.

```
CLI default region: eu-west-1
CLI output format:  json
CLI profile name:   traineeship
```

### Logging in

```shell
aws sso login --profile traineeship
```

This opens a browser session. Once authenticated, the profile is valid for the duration of the SSO
session (typically 8 hours).

### Validating access

```shell
aws sts get-caller-identity --profile traineeship
```

If the command succeeds, it returns your assumed user ARN and account ID.

### Setting a default profile

To avoid passing `--profile traineeship` to every command, set it as your default:

=== "Linux / macOS"

    ```shell
    export AWS_PROFILE=traineeship
    ```

=== "Windows (PowerShell)"

    ```powershell
    $env:AWS_PROFILE = "traineeship"
    ```
