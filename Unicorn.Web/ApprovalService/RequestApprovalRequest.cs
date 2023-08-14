// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json.Serialization;

namespace Unicorn.Web.ApprovalService;

/// <summary>
/// Represents an event when the publication is approved.
/// </summary>
[Serializable]
public class RequestApprovalRequest
{
    [JsonPropertyName("property_id")]
    public string PropertyId { get; set; } = null!;
}

