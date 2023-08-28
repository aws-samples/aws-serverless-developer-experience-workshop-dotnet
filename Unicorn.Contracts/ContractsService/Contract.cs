// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Text.Json.Serialization;
using Amazon.DynamoDBv2.DataModel;

namespace Unicorn.Contracts.ContractService;

/// <summary>
/// Class that represents a Unicorn Properties Contract
/// </summary>
[Serializable]
public class Contract
{
    [DynamoDBHashKey] public string? PropertyId { get; init; }

    public Guid ContractId { get; init; }

    public string ContractStatus { get; set; } = Unicorn.Contracts.ContractService.ContractStatus.Draft;

    public DateTime ContractCreated { get; } = DateTime.Now;

    public DateTime ContractLastModifiedOn { get; set; } = DateTime.Now;

    public Address? Address { get; set; }

    public string? SellerName { get; set; }
}

/// <summary>
/// Class that represents a Contract address
/// </summary>
[Serializable]
public class Address
{
    public Address()
    {
    }

    [JsonPropertyName("number")] public int Number { get; set; }
    [JsonPropertyName("street")] public string? Street { get; set; }
    [JsonPropertyName("city")] public string? City { get; set; }
    [JsonPropertyName("country")] public string Country { get; } = "USA";
}

/// <summary>
/// This class represents the structure of a request body to create a new contract.
/// </summary>
public class CreateContractRequest
{
    [JsonPropertyName("property_id")] public string? PropertyId { get; set; }  
    [JsonPropertyName("address")] public Address? Address { get; set; }
    [JsonPropertyName("seller_name")] public string? SellerName { get; set; }
}

/// <summary>
/// This class represents the structure of a request body to create a new contract.
/// </summary>
public class UpdateContractRequest
{
    [JsonPropertyName("property_id")] public string? PropertyId { get; set; }
}