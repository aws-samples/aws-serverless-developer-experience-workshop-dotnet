// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Collections.Generic;
using Amazon.DynamoDBv2.Model;

namespace Unicorn.Contracts.ContractService;

/// <summary>
/// Class that represents a Unicorn Properties Contract
/// </summary>
[Serializable]
public class Contract
{
    public string? PropertyId { get; set; }

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

    public int Number { get; set; }
    public string? Street { get; set; }
    public string? City { get; set; }
    public string Country { get; } = "USA";
    
    public Dictionary<string, AttributeValue> ToMap()
    {
        
        return new Dictionary<string, AttributeValue>(){
            { "Number", new AttributeValue { N = this.Number.ToString() } },
            { "Street", new AttributeValue { S = this.Street } },
            { "City", new AttributeValue { S = this.City } },
            { "Country", new AttributeValue { S = this.Country } },
        };
    }
    
}

/// <summary>
/// This class represents the structure of a request body to create a new contract.
/// </summary>
public class CreateContractRequest
{
    public string? PropertyId { get; set; }  
    public Address? Address { get; set; }
    public string? SellerName { get; set; }
}

/// <summary>
/// This class represents the structure of a request body to create a new contract.
/// </summary>
public class UpdateContractRequest
{
    public string? PropertyId { get; set; }
}