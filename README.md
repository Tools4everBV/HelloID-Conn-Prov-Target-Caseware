# HelloID-Conn-Prov-Target-Caseware

<!--
** for extra information about alert syntax please refer to [Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
-->

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Caseware](#helloid-conn-prov-target-caseware)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported  features](#supported--features)
  - [Getting started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Initial validation / correlation based on `email`](#initial-validation--correlation-based-on-email)
    - [No account creation](#no-account-creation)
    - [`OwnerType` is a required property when updating accounts](#ownertype-is-a-required-property-when-updating-accounts)
    - [No property to enable or disable](#no-property-to-enable-or-disable)
    - [Memberships / roles](#memberships--roles)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Caseware_ is a _target_ connector. _Caseware_ provides a set of REST API's that allow you to programmatically interact with its data.

## Supported  features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks |
| ----------------------------------------- | --------- | --------------------------------------- | ------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable, Delete |         |
| **Permissions**                           | ✅         | -                                       |         |
| **Resources**                             | ❌         | -                                       |         |
| **Entitlement Import: Accounts**          | ✅         | -                                       |         |
| **Entitlement Import: Permissions**       | ❌            | -                                       |         |
| **Governance Reconciliation Resolutions** | ✅         | -                                       |         |

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                        | Mandatory |
| ------------ | ---------------------------------- | --------- |
| ClientId     | The UserName to connect to the API | Yes       |
| ClientSecret | The Password to connect to the API | Yes       |
| BaseUrl      | The URL to the API                 | Yes       |
| CustomerId   | The _id_ or _name_ of the customer | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Caseware_ to a person in _HelloID_.

| Setting                   | Value                                                          |
| ------------------------- | -------------------------------------------------------------- |
| Enable correlation        | `True`                                                         |
| Person correlation field  | `PersonContext.Person.Account.Microsoft.ActiveDirectory.Email` |
| Account correlation field | `Email`                                                        |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the property `CWGuid` property from _Caseware_

## Remarks

### Initial validation / correlation based on `email`

Within the _create_ lifecycle action, initial validation and correlation of the user account is based on the `email` attribute. The `accountReference` will be the ` CWGuid` property.

### No account creation

This connector does not create new accounts. The _create_ lifecycle actions only performs account correlation. Subsequently; the `$actionContext.DryRun` logic has been removed.

### `OwnerType` is a required property when updating accounts

When performing an update, the OwnerType field must be present and valid in the payload.

### No property to enable or disable

There's no property to _enable_ or _disable_ the user account. Caseware does provide a _CanLogin_ property. However, its not possible to change the value of this property since its tied directly to an external user synchronization.

### Memberships / roles

Groups are assigned through roles. Just like _users_, roles also have a `CWGuid`. This GUID is used when assigning and removing roles. However, the `id` of a role is what you will find on a _user_ in the field `FirmWideRoleIds`. These _ids_ correspond to the _ids_ associated with a role.

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint                             | Description          |
| ------------------------------------ | -------------------- |
| {baseUrl}/ms/caseware-cloud/api/v2/auth/token | Retrieve oAuth token |
| {baseUrl}/ms/caseware-cloud/api/v2/users      | User related actions |
| {baseUrl}/ms/caseware-cloud/api/v2/users/:id/role-assignments      | Grant / revoke role |
| {baseUrl}/ms/caseware-cloud/api/v2/groups/{groupId}/user-assignments      | Grant / revoke role |
| {baseUrl}/ms/caseware-cloud/api/v2/roles      | Retrieve available roles |
| {baseUrl}/ms/caseware-cloud/api/v2/groups      | Retrieve available groups |

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
