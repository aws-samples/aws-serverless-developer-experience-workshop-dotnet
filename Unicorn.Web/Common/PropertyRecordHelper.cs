// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

namespace Unicorn.Web.Common;

/// <summary>
/// This class contains helper methods for PropertyRecord class
/// </summary>
public static class PropertyRecordHelper
{
    public static PropertyDto ToDto(PropertyRecord property)
    {
        return new PropertyDto
        {
            Country = property.Country,
            City = property.City,
            Street = property.Street,
            PropertyNumber = property.PropertyNumber,
            Description = property.Description,
            Contract = property.Contract,
            ListPrice = property.ListPrice,
            Currency = property.Currency,
            Images = property.Images,
            Status = property.Status
        };
    }
    
    
    /// <summary>
    /// Extract the parts of the Property ID to get the PK and SK
    /// components for a table query
    /// </summary>
    /// <param name="propertyId">Property ID</param>
    /// <returns>Dictionary of PK and SK </returns>
    public static Dictionary<string, string> ParsePropertyId(string propertyId)
    {
        var splitString = propertyId.Split('/');
        var country = splitString[0];
        var city = splitString[1];
        var street = splitString[2];
        var number = splitString[3];

        var keys = new Dictionary<string, string>()
        {
            { "pk", GetPartitionKey(country, city) },
            { "sk", GetSortKey(street, number) }
        };

        return keys;
    }
    public static string GetPartitionKey(string country, string city)
    {
        var pkDetails = $"{country}#{city}".Replace(' ', '-').ToLower();
        return $"property#{pkDetails}";
    }
    
    public static string GetSortKey(string street, string propertyNumber)
    {
        return $"{street}#{propertyNumber}".Replace(' ', '-').ToLower();
    }
}
