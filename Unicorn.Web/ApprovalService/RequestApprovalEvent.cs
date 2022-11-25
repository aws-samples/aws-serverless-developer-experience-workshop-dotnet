// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json.Serialization;
using Unicorn.Web.Common;

namespace Unicorn.Web.ApprovalService;

/// <summary>
/// Represents an event when the publication is approved.
/// </summary>
[Serializable]
public class RequestApprovalEvent
{
    [JsonPropertyName(PropertyNames.PropertyId)]
    public string PropertyId { get; set; } = null!;
    
    [JsonPropertyName(PropertyNames.Status)]
    public string Status { get; set; } = null!;
    
    [JsonPropertyName(PropertyNames.Description)]
    public string Description { get; set; }  = null!;
    
    [JsonPropertyName(PropertyNames.Address)]
    public RequestApprovalEventAddress Address { get; set; } = null!;
    
    [JsonPropertyName(PropertyNames.Images)]
    public List<string> Images { get; set; }  = null!;
}

[Serializable]
public class RequestApprovalEventAddress
{
    [JsonPropertyName(PropertyNames.Country)]
    public string Country { get; set; } = null!;
       
    [JsonPropertyName(PropertyNames.City)]
    public string City { get; set; }  = null!;
        
    [JsonPropertyName(PropertyNames.Street)]
    public string Street { get; set; }  = null!;
        
    [JsonPropertyName(PropertyNames.Number)]
    public string Number { get; set; }  = null!;
}