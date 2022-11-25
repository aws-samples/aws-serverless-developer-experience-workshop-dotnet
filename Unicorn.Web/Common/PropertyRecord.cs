// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json.Serialization;
using Amazon.DynamoDBv2.DataModel;

namespace Unicorn.Web.Common;

/// <summary>
/// Class that represents a Unicorn Property record
/// </summary>
[Serializable]
public class PropertyRecord
{
    [JsonIgnore]
    private string? _pk;
        
    [JsonIgnore]
    private string? _sk;

    private string GetPartitionKey()
    {
        return PropertyRecordHelper.GetPartitionKey(Country, City);
    }
        
    private string GetSortKey()
    {
        return PropertyRecordHelper.GetSortKey(Street, PropertyNumber);
    }

    [DynamoDBHashKey]
    [JsonPropertyName(PropertyNames.PrimaryKey)]
    public string PK
    {
        get => _pk ??= GetPartitionKey();
        set => _pk = value;
    }

    [DynamoDBRangeKey]
    [JsonPropertyName(PropertyNames.SortKey)]
    public string SK
    {
        get => _sk ??= GetSortKey();
        set => _sk = value;
    }

    [JsonPropertyName(PropertyNames.Country)]
    [DynamoDBProperty(PropertyNames.Country)]
    public string Country { get; set; } = null!;
        
    [JsonPropertyName(PropertyNames.City)]
    [DynamoDBProperty(PropertyNames.City)]
    public string City { get; set; }  = null!;
        
    [JsonPropertyName(PropertyNames.Street)]
    [DynamoDBProperty(PropertyNames.Street)]
    public string Street { get; set; }  = null!;
        
    [JsonPropertyName(PropertyNames.Number)]
    [DynamoDBProperty(PropertyNames.Number)]
    public string PropertyNumber { get; set; }  = null!;
        
    [JsonPropertyName(PropertyNames.Description)]
    [DynamoDBProperty(PropertyNames.Description)]
    public string Description { get; set; }  = null!;
        
    [JsonPropertyName(PropertyNames.Contract)]
    [DynamoDBProperty(PropertyNames.Contract)]
    public string Contract { get; set; }  = null!;
        
    [JsonPropertyName(PropertyNames.ListPrice)]
    [DynamoDBProperty(PropertyNames.ListPrice)]
    public decimal ListPrice { get; set; }
        
    [JsonPropertyName(PropertyNames.Currency)]
    [DynamoDBProperty(PropertyNames.Currency)]
    public string Currency { get; set; }  = null!;
        
    [JsonPropertyName(PropertyNames.Images)]
    [DynamoDBProperty(PropertyNames.Images)]
    public List<string> Images { get; set; }  = null!;
        
    [JsonPropertyName(PropertyNames.Status)]
    [DynamoDBProperty(PropertyNames.Status)]
    public string Status { get; set; } = null!;
}