// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json.Serialization;
using Unicorn.Web.Common;

namespace Unicorn.Web.PublicationManagerService;

/// <summary>
/// Represents an event when the publication is approved.
/// </summary>
[Serializable]
public class PublicationEvaluationCompletedEvent
{
    [JsonPropertyName(PropertyNames.PropertyId)]
    public string PropertyId { get; set; }  = null!;

    [JsonPropertyName(PropertyNames.EvaluationResult)]
    public string EvaluationResult { get; set; } = null!;
}