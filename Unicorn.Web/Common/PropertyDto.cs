// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json.Serialization;

namespace Unicorn.Web.Common;

/// <summary>
/// Class that represents a Unicorn Property Data Transfer Object
/// </summary>
[Serializable]
public class PropertyDto
{
    [JsonPropertyName("country")]
    public string Country { get; set; } = null!;
        
    [JsonPropertyName("city")]
    public string City { get; set; }  = null!;
        
    [JsonPropertyName("street")]
    public string Street { get; set; }  = null!;
      
    [JsonPropertyName("number")]
    public string PropertyNumber { get; set; }  = null!;
        
    [JsonPropertyName("description")]
    public string Description { get; set; }  = null!;
        
    [JsonPropertyName("contract")]
    public string Contract { get; set; }  = null!;
        
    [JsonPropertyName("listprice")]
    public decimal ListPrice { get; set; }
        
    [JsonPropertyName("currency")]
    public string Currency { get; set; }  = null!;
        
    [JsonPropertyName("images")]
    public List<string> Images { get; set; }  = null!;

    [JsonPropertyName("status")]
    public string Status { get; set; } = null!;
}