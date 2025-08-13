// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

namespace Unicorn.Web.PublicationManagerService;

/// <summary>
/// Represents an event when the publication is approved.
/// </summary>
[Serializable]
public class ApprovePublicationRequest
{ 
    public string PropertyId { get; set; } = null!;
}

