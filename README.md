# Zendesk_Ticketing
Implement Basic Auth Using Zendesk For Ticketing

Link for the zendesk API Docummentation : 
https://developer.zendesk.com/api-reference/ticketing/tickets/tickets/#json-format

# Salesforce → Zendesk Ticketing Integration (Apex)

Automatically creates a Zendesk ticket whenever a Salesforce Case is inserted, using Apex triggers, a handler class, and a reusable utility class.

---

## Table of Contents

- [Overview](#overview)
- [Architecture & Flow](#architecture--flow)
- [Components](#components)
  - [zendeskTicketUtils](#zendesktticketutils)
  - [CaseTriggerHandler](#casetriggerhandler)
  - [CaseTrigger](#casetrigger)
- [Custom Labels Setup](#custom-labels-setup)
- [Remote Site Settings](#remote-site-settings)
- [Field Mapping](#field-mapping)
- [Error Handling](#error-handling)
- [Known Limitations & Improvements](#known-limitations--improvements)
- [Quick Test (Anonymous Apex)](#quick-test-anonymous-apex)

---

## Overview

When a new **Case** is created in Salesforce, a **Zendesk Ticket** is automatically created via the Zendesk REST API. The integration uses:

- A **trigger** on the `Case` object (after insert)
- A **handler class** (`CaseTriggerHandler`) that processes new cases and dispatches the callout
- A **utility class** (`zendeskTicketUtils`) that builds and sends the HTTP request to Zendesk

Authentication to Zendesk is done via **HTTP Basic Auth**, with credentials stored securely in Salesforce **Custom Labels**.

---

## Architecture & Flow

```
Case Inserted (Salesforce)
        │
        ▼
  CaseTrigger
  (after insert)
        │
        ▼
  CaseTriggerHandler.handleCaseAfterInsert()
        │
        ├─── Guard: skip if Batch or Future context
        │
        ├─── Build TicketWrapper from Case fields
        │
        └─── makeCallout(JSON.serialize(wrapper))   ← @future(callout=true)
                    │
                    ▼
        zendeskTicketUtils.createTicket(wrapper)
                    │
                    ▼
        POST https://yourdomain.zendesk.com/api/v2/tickets.json
                    │
              ┌─────┴──────┐
           201 Created   Error
           (success)    (logged)
```

> **Why `@future`?** Salesforce does not allow HTTP callouts in the same transaction as DML operations (like inserting a Case). The `@future(callout=true)` annotation moves the callout to an asynchronous context, which is a requirement for callouts triggered by DML.

---

## Components

---

### `zendeskTicketUtils`

**File:** `zendeskTicketUtils.cls`
**Access:** `public with sharing`

The core utility class. It defines the `TicketWrapper` data model and the `createTicket` method that sends the HTTP POST request to Zendesk.

---

#### Inner Class: `TicketWrapper`

A simple data container (DTO) used to pass ticket information between classes. All fields are `public String`.

| Field      | Type     | Description                                                  | Required |
|------------|----------|--------------------------------------------------------------|----------|
| `subject`  | `String` | The title/subject of the Zendesk ticket                      | Yes      |
| `body`     | `String` | The first comment/description of the ticket                  | Yes      |
| `priority` | `String` | Ticket priority. Must be one of: `low`, `normal`, `high`, `urgent` | Yes |
| `name`     | `String` | Full name of the ticket requester                            | Yes      |
| `email`    | `String` | Email address of the ticket requester                        | Yes      |

**Example instantiation:**
```apex
zendeskTicketUtils.TicketWrapper wrapper = new zendeskTicketUtils.TicketWrapper();
wrapper.subject  = 'Login issue';
wrapper.body     = 'User cannot log in since the latest update.';
wrapper.priority = 'high';
wrapper.name     = 'Jane Smith';
wrapper.email    = 'jane.smith@example.com';
```

---

#### Method: `createTicket`

```apex
public static void createTicket(TicketWrapper wrapper)
```

Builds and sends an HTTP POST request to the Zendesk Tickets API. This method is **synchronous** — it must be called from an asynchronous context (e.g., `@future`, Queueable, Batch) to comply with Salesforce callout-after-DML restrictions.

**Parameters**

| Parameter | Type            | Description                          |
|-----------|-----------------|--------------------------------------|
| `wrapper` | `TicketWrapper` | The ticket data to send to Zendesk   |

**Authentication**

Reads credentials from two Salesforce Custom Labels and encodes them as Base64 for HTTP Basic Auth:

| Custom Label           | Purpose                              |
|------------------------|--------------------------------------|
| `Zendesk_Username`     | Zendesk agent email address          |
| `Zendesk_Api_Token`    | Zendesk API token                    |

The header is constructed as:
```
Authorization: Basic base64(Zendesk_Username:Zendesk_Api_Token)
```

**HTTP Request Details**

| Property       | Value                                               |
|----------------|-----------------------------------------------------|
| Endpoint       | `https://yourdomain.zendesk.com/api/v2/tickets.json` |
| Method         | `POST`                                              |
| Content-Type   | `application/json`                                  |
| Accept         | `application/json`                                  |

**Request Body (JSON)**
```json
{
  "ticket": {
    "subject": "<wrapper.subject>",
    "comment": { "body": "<wrapper.body>" },
    "priority": "<wrapper.priority>",
    "requester": {
      "name": "<wrapper.name>",
      "email": "<wrapper.email>"
    }
  }
}
```

**Response Handling**

| HTTP Status | Behaviour                                                  |
|-------------|------------------------------------------------------------|
| `201`       | Success — logs `Ticket created successfully` via `System.debug` |
| Any other   | Logs the status code and response body via `System.debug`  |

**Exception Handling**

| Exception               | Handler                              |
|-------------------------|--------------------------------------|
| `System.CalloutException` | Caught and logged via `System.debug` |
| `Exception`             | Caught and logged via `System.debug` |

> ⚠️ **Note:** Currently errors are only logged to debug logs. For production use, consider publishing a Platform Event or inserting an error log record so failures are visible outside of debug sessions.

---

### `CaseTriggerHandler`

**File:** `CaseTriggerHandler.cls`
**Access:** `public with sharing`

The trigger handler class. It separates business logic from the trigger itself, following the standard single-trigger / handler pattern.

---

#### Method: `handleCaseAfterInsert`

```apex
public static void handleCaseAfterInsert(List<Case> newRecords)
```

Called by `CaseTrigger` with the list of newly inserted Cases. Iterates over each Case, builds a `TicketWrapper`, and dispatches the callout asynchronously via `makeCallout`.

**Parameters**

| Parameter    | Type          | Description                              |
|--------------|---------------|------------------------------------------|
| `newRecords` | `List<Case>`  | The list of newly inserted Case records  |

**Guard Clause**

The method immediately returns (no-op) if called from a batch or future context, preventing nested future call errors:

```apex
if (System.isBatch() || System.isFuture()) {
    return;
}
```

**Field Mapping from Case to TicketWrapper**

| Case Field       | TicketWrapper Field | Transformation                                    |
|------------------|---------------------|---------------------------------------------------|
| `c.Description`  | `wrapper.body`      | Direct assignment                                 |
| `c.Subject`      | `wrapper.subject`   | Direct assignment                                 |
| `c.Priority`     | `wrapper.priority`  | `.toLowerCase()` — Zendesk requires lowercase     |
| *(hardcoded)*    | `wrapper.name`      | Currently `'name'` — **must be replaced** with a Contact query |
| *(hardcoded)*    | `wrapper.email`     | Currently `'email'` — **must be replaced** with a Contact query |

> ⚠️ **Known Gap:** The `name` and `email` fields are hardcoded placeholders. In production, you should query the `Contact` associated with `c.ContactId` to populate these fields correctly. See [Known Limitations & Improvements](#known-limitations--improvements).

---

#### Method: `makeCallout`

```apex
@future(callout=true)
private static void makeCallout(String params)
```

A `@future` method that deserializes the serialized `TicketWrapper` JSON string back into an object and calls `zendeskTicketUtils.createTicket`. This is required because Salesforce prohibits direct HTTP callouts in the same synchronous transaction as a DML operation (Case insert).

**Parameters**

| Parameter | Type     | Description                                         |
|-----------|----------|-----------------------------------------------------|
| `params`  | `String` | JSON-serialized `TicketWrapper` string              |

**Why serialize/deserialize?**

`@future` methods only accept primitive types or collections of primitives as parameters. Since `TicketWrapper` is a custom class, it must be converted to a `String` using `JSON.serialize()` before passing, then reconstructed with `JSON.deserialize()` inside the future method.

```apex
// In handleCaseAfterInsert:
makeCallout(JSON.serialize(wrapper));

// Inside makeCallout:
zendeskTicketUtils.TicketWrapper wrapper =
    (zendeskTicketUtils.TicketWrapper) JSON.deserialize(
        params,
        zendeskTicketUtils.TicketWrapper.class
    );
```

---

### `CaseTrigger`

**File:** `CaseTrigger.trigger`
**Object:** `Case`
**Events:** `after insert`

A minimal trigger that delegates all logic to `CaseTriggerHandler`. This keeps the trigger itself clean and the business logic testable.

```apex
trigger CaseTrigger on Case (after insert) {
    CaseTriggerHandler.handleCaseAfterInsert(Trigger.new);
}
```

| Property       | Value                              |
|----------------|------------------------------------|
| Object         | `Case`                             |
| Trigger Event  | `after insert`                     |
| Handler        | `CaseTriggerHandler.handleCaseAfterInsert` |
| `Trigger.new`  | List of newly inserted Case records |

> The trigger fires **after** the insert (not before) because it needs the Case to be committed with a valid `Id` and full field data before dispatching the callout.

---

## Custom Labels Setup

Create the following Custom Labels in Salesforce under **Setup → Custom Labels**:

| Label Name          | Value                              | Description                      |
|---------------------|------------------------------------|----------------------------------|
| `Zendesk_Username`  | `your-agent@yourcompany.com`       | Zendesk agent email address      |
| `Zendesk_Api_Token` | `your_api_token_here`              | Zendesk API token (not password) |

> Custom Labels are accessed in Apex via `System.label.Label_Name`. They are a safe way to store non-secret configuration. For storing secrets in a higher-security environment, consider **Named Credentials** instead (see [Known Limitations & Improvements](#known-limitations--improvements)).

---

## Remote Site Settings

Before the callout can succeed, the Zendesk domain must be whitelisted in Salesforce.

1. Go to **Setup → Security → Remote Site Settings**
2. Click **New Remote Site**
3. Fill in:

| Field              | Value                                   |
|--------------------|-----------------------------------------|
| Remote Site Name   | `Zendesk`                               |
| Remote Site URL    | `https://yourdomain.zendesk.com`        |
| Active             | ✅ Checked                              |

---

## Field Mapping

Summary of how Salesforce Case fields map to the Zendesk Ticket API payload:

| Salesforce Case Field | Zendesk Ticket Field          | Notes                                              |
|-----------------------|-------------------------------|----------------------------------------------------|
| `Subject`             | `ticket.subject`              |                                                    |
| `Description`         | `ticket.comment.body`         |                                                    |
| `Priority`            | `ticket.priority`             | Lowercased — Zendesk accepts `low/normal/high/urgent` |
| `Contact.Name`        | `ticket.requester.name`       | ⚠️ Currently hardcoded — requires Contact query    |
| `Contact.Email`       | `ticket.requester.email`      | ⚠️ Currently hardcoded — requires Contact query    |

---

## Error Handling

| Scenario                          | Current Behaviour                            | Recommended Improvement                     |
|-----------------------------------|----------------------------------------------|---------------------------------------------|
| HTTP non-201 response             | `System.debug` log only                      | Insert error log record or fire Platform Event |
| `CalloutException`                | `System.debug` log only                      | Retry logic or alert mechanism              |
| Generic `Exception`               | `System.debug` log only                      | Same as above                               |
| Batch/Future context guard        | Returns immediately (no callout)             | Consider a Queueable for batch scenarios    |
| Missing Contact on Case           | Sends hardcoded `'name'` / `'email'` strings | Query `Contact` by `c.ContactId`            |

---

## Known Limitations & Improvements

**1. Hardcoded requester name and email**
The `wrapper.name` and `wrapper.email` fields in `CaseTriggerHandler` are set to placeholder strings. This must be fixed by querying the related Contact:

```apex
// Suggested fix inside the for loop:
Contact con = [SELECT Name, Email FROM Contact WHERE Id = :c.ContactId LIMIT 1];
wrapper.name  = con.Name;
wrapper.email = con.Email;
```

Note: SOQL inside a loop is a governor limit risk. Move the query outside the loop using a `Map<Id, Contact>` pattern for bulk safety.

**2. No bulk-safe SOQL**
The current implementation processes one Case per iteration without batching SOQL queries. If many Cases are inserted simultaneously, this will hit governor limits. Use a Map-based pre-query pattern:

```apex
Set<Id> contactIds = new Set<Id>();
for (Case c : newRecords) { contactIds.add(c.ContactId); }
Map<Id, Contact> contactMap = new Map<Id, Contact>(
    [SELECT Id, Name, Email FROM Contact WHERE Id IN :contactIds]
);
```

**3. Callout is fired twice**
In the current code, `zendeskTicketUtils.createTicket(wrapper)` is called synchronously AND via `makeCallout()`. This will create duplicate tickets. The direct synchronous call should be removed — only `makeCallout()` should invoke `createTicket`.

**4. Use Named Credentials instead of Custom Labels**
For better security, replace the manual Basic Auth header construction with a Salesforce **Named Credential**. Named Credentials handle authentication automatically and do not expose tokens in Custom Labels.

**5. No test classes included**
Apex test classes with mock HTTP callouts (`HttpCalloutMock`) should be added to achieve the required 75%+ code coverage for deployment to production.

---

## Quick Test (Anonymous Apex)

Use the following in the **Developer Console → Execute Anonymous** window to test `createTicket` directly without inserting a Case:

```apex
zendeskTicketUtils.TicketWrapper wrapper = new zendeskTicketUtils.TicketWrapper();
wrapper.subject  = 'Test Ticket';
wrapper.body     = 'This is a test ticket created from Salesforce.';
wrapper.priority = 'normal';
wrapper.name     = 'John Doe';
wrapper.email    = 'john.doe@example.com';

zendeskTicketUtils.createTicket(wrapper);
```

Check the **Debug Logs** for the response. A `201` status confirms the ticket was created successfully in Zendesk.
