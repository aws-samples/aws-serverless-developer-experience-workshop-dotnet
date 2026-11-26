// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Collections.Generic;
using System.Globalization;
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

    /// <summary>
    /// Creation time as a <see cref="ContractTimestamp"/> string.
    /// </summary>
    public required string ContractCreated { get; init; }

    /// <summary>
    /// Last modification time as a <see cref="ContractTimestamp"/> string.
    /// </summary>
    public required string ContractLastModifiedOn { get; set; }

    public Address? Address { get; set; }

    public string? SellerName { get; set; }
}

/// <summary>
/// Formats the contract timestamps stored in DynamoDB as strings.
/// The form is <c>yyyy-MM-ddTHH:mm:ssZ</c>: UTC, whole seconds (any fraction is truncated), literal <c>Z</c>.
/// Every value has the same width, so comparing the strings orders them by time.
/// </summary>
public static class ContractTimestamp
{
    private const string Format = "yyyy-MM-dd'T'HH:mm:ss'Z'";

    /// <summary>
    /// Formats an instant as a contract timestamp. A non-UTC value is converted to UTC first.
    /// </summary>
    public static string From(DateTime instant) =>
        instant.ToUniversalTime().ToString(Format, CultureInfo.InvariantCulture);

    /// <summary>
    /// The current instant as a contract timestamp.
    /// </summary>
    public static string Now() => From(DateTime.UtcNow);
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