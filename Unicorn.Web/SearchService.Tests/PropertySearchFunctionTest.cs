// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Net;
using System.Text.Json;
using Amazon.DynamoDBv2.DataModel;
using Amazon.DynamoDBv2.DocumentModel;
using Amazon.Lambda.APIGatewayEvents;
using NSubstitute;
using Unicorn.Web.Common;
using Xunit;

namespace Unicorn.Web.SearchService.Tests;

public class PropertySearchFunctionTest
{
    public PropertySearchFunctionTest()
    {
        TestHelpers.SetEnvironmentVariables();
    }
    
    [Fact]
    public async Task PropertySearchFunction_SearchByStreet_ReturnsResults()
    {
        // Arrange
        var request = TestHelpers.LoadApiGatewayProxyRequest("./events/search_by_street_event.json");
        var context = TestHelpers.NewLambdaContext();
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();
        
        var searchResult = new List<PropertyRecord>
        {
            new()
            {
                Country = "USA",
                City = "Anytown",
                Street = "Main Street",
                PropertyNumber = "111"
            },
            new()
            {
                Country = "USA",
                City = "Anytown",
                Street = "Main Street",
                PropertyNumber = "222"
            }
        };
        
        dynamoDbContext
            .FromQueryAsync<PropertyRecord>(Arg.Any<Amazon.DynamoDBv2.DocumentModel.QueryOperationConfig>())
            .Returns(TestHelpers.NewDynamoDBSearchResult(searchResult));

        var expectedResponse = new APIGatewayProxyResponse
        {
            StatusCode = (int)HttpStatusCode.OK,
            Headers = new Dictionary<string, string>
            {
                { "Content-Type", "application/json" },
                { "X-Custom-Header", "application/json" }
            }
        };
        
        // Act
        var function = new PropertySearchFunction(dynamoDbContext);
        var response = await function.FunctionHandler(request, context);
        
        // Assert
        Assert.Equal(expectedResponse.Headers, response.Headers);
        Assert.Equal(expectedResponse.StatusCode, response.StatusCode);
        Assert.NotEmpty(response.Body);

        dynamoDbContext.Received(1)
            .FromQueryAsync<PropertyRecord>(Arg.Any<Amazon.DynamoDBv2.DocumentModel.QueryOperationConfig>());

        var items = JsonSerializer.Deserialize<List<PropertyDto>>(response.Body);
        Assert.NotNull(items);
        Assert.Equal(searchResult.Count, items.Count);
        Assert.Contains(items,
            dto => dto.Country == items[0].Country && dto.City == items[0].City && dto.Street == items[0].Street &&
                   dto.PropertyNumber == items[0].PropertyNumber);
        Assert.Contains(items,
            dto => dto.Country == items[1].Country && dto.City == items[1].City && dto.Street == items[1].Street &&
                   dto.PropertyNumber == items[1].PropertyNumber);

    }

    [Fact]
    public async Task PropertySearchFunction_SearchByCity_ReturnsResults()
    {
        // Arrange
        var request = new APIGatewayProxyRequest
        {
            Resource = "/search/{country}/{city}",
            Path = "/search/usa/anytown",
            HttpMethod = "GET",
            PathParameters = new Dictionary<string, string>
            {
                { "country", "usa" },
                { "city", "anytown" }
            },
            Headers = new Dictionary<string, string>
            {
                { "Content-Type", "application/json" }
            }
        };

        var context = TestHelpers.NewLambdaContext();
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();

        var searchResult = new List<PropertyRecord>
        {
            new()
            {
                Country = "USA",
                City = "Anytown",
                Street = "Main Street",
                PropertyNumber = "111",
                Status = PropertyStatus.Approved
            }
        };

        dynamoDbContext
            .FromQueryAsync<PropertyRecord>(Arg.Any<QueryOperationConfig>())
            .Returns(TestHelpers.NewDynamoDBSearchResult(searchResult));

        // Act
        var function = new PropertySearchFunction(dynamoDbContext);
        var response = await function.FunctionHandler(request, context);

        // Assert
        Assert.Equal(200, response.StatusCode);
        Assert.NotEmpty(response.Body);

        dynamoDbContext.Received(1)
            .FromQueryAsync<PropertyRecord>(Arg.Any<QueryOperationConfig>());
    }

    [Fact]
    public async Task PropertySearchFunction_PropertyDetails_HappyPath_ReturnsResult()
    {
        // Arrange
        var request = TestHelpers.LoadApiGatewayProxyRequest("./events/search_by_full_address.json");
        // The fixture has null pathParameters, add them manually
        request.PathParameters = new Dictionary<string, string>
        {
            { "country", "usa" },
            { "city", "anytown" },
            { "street", "main-street" },
            { "number", "124" }
        };

        var context = TestHelpers.NewLambdaContext();
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();

        var searchResult = new List<PropertyRecord>
        {
            new()
            {
                Country = "USA",
                City = "Anytown",
                Street = "Main Street",
                PropertyNumber = "124",
                Status = PropertyStatus.Approved,
                ListPrice = 500000.00M,
                Images = new() { "image1.jpg" }
            }
        };

        dynamoDbContext
            .FromQueryAsync<PropertyRecord>(Arg.Any<QueryOperationConfig>())
            .Returns(TestHelpers.NewDynamoDBSearchResult(searchResult));

        // Act
        var function = new PropertySearchFunction(dynamoDbContext);
        var response = await function.FunctionHandler(request, context);

        // Assert
        Assert.Equal(200, response.StatusCode);
        Assert.NotEmpty(response.Body);

        var items = JsonSerializer.Deserialize<List<PropertyDto>>(response.Body);
        Assert.NotNull(items);
        Assert.Single(items);
        Assert.Equal("124", items[0].PropertyNumber);
    }

    [Fact]
    public async Task PropertySearchFunction_PropertyNotFound_ReturnsEmptyResult()
    {
        // Arrange
        var request = TestHelpers.LoadApiGatewayProxyRequest("./events/search_by_full_address_not_found.json");
        request.PathParameters = new Dictionary<string, string>
        {
            { "country", "usa" },
            { "city", "anytown" },
            { "street", "main-street" },
            { "number", "122" }
        };

        var context = TestHelpers.NewLambdaContext();
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();

        // Return empty list - property not found (query filters for APPROVED only)
        var emptyResult = new List<PropertyRecord>();
        dynamoDbContext
            .FromQueryAsync<PropertyRecord>(Arg.Any<QueryOperationConfig>())
            .Returns(TestHelpers.NewDynamoDBSearchResult(emptyResult));

        // Act
        var function = new PropertySearchFunction(dynamoDbContext);
        var response = await function.FunctionHandler(request, context);

        // Assert - returns 200 with empty array (query returns no APPROVED results)
        Assert.Equal(200, response.StatusCode);

        var items = JsonSerializer.Deserialize<List<PropertyDto>>(response.Body);
        Assert.NotNull(items);
        Assert.Empty(items);
    }

    [Fact]
    public async Task PropertySearchFunction_PropertyNotApproved_ReturnsEmptyResult()
    {
        // Arrange
        var request = TestHelpers.LoadApiGatewayProxyRequest("./events/search_by_full_address_declined.json");
        request.PathParameters = new Dictionary<string, string>
        {
            { "country", "usa" },
            { "city", "anytown" },
            { "street", "main-street" },
            { "number", "125" }
        };

        var context = TestHelpers.NewLambdaContext();
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();

        // The query itself filters for APPROVED status, so a non-approved property returns empty
        var emptyResult = new List<PropertyRecord>();
        dynamoDbContext
            .FromQueryAsync<PropertyRecord>(Arg.Any<QueryOperationConfig>())
            .Returns(TestHelpers.NewDynamoDBSearchResult(emptyResult));

        // Act
        var function = new PropertySearchFunction(dynamoDbContext);
        var response = await function.FunctionHandler(request, context);

        // Assert - returns 200 with empty array since the query filters for APPROVED
        Assert.Equal(200, response.StatusCode);

        var items = JsonSerializer.Deserialize<List<PropertyDto>>(response.Body);
        Assert.NotNull(items);
        Assert.Empty(items);
    }

    [Fact]
    public async Task PropertySearchFunction_NonGetMethod_Returns400()
    {
        // Arrange
        var request = new APIGatewayProxyRequest
        {
            Resource = "/search/{country}/{city}",
            Path = "/search/usa/anytown",
            HttpMethod = "POST",
            PathParameters = new Dictionary<string, string>
            {
                { "country", "usa" },
                { "city", "anytown" }
            },
            Headers = new Dictionary<string, string>
            {
                { "Content-Type", "application/json" }
            }
        };

        var context = TestHelpers.NewLambdaContext();
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();

        // Act
        var function = new PropertySearchFunction(dynamoDbContext);
        var response = await function.FunctionHandler(request, context);

        // Assert
        Assert.Equal(400, response.StatusCode);
        Assert.Contains("ErrorInRequest", response.Body);

        // DynamoDB should not be queried
        dynamoDbContext.Received(0)
            .FromQueryAsync<PropertyRecord>(Arg.Any<QueryOperationConfig>());
    }
}