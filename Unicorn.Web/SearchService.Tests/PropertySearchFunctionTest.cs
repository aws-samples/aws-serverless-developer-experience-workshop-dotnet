// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Net;
using System.Text.Json;
using Amazon.DynamoDBv2.DataModel;
using Amazon.DynamoDBv2.DocumentModel;
using Amazon.Lambda.APIGatewayEvents;
using Moq;
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
        
        var mockDynamoDbContext = new Mock<IDynamoDBContext>();
        mockDynamoDbContext.Setup(c =>
                c.FromQueryAsync<PropertyRecord>(It.IsAny<QueryOperationConfig>(), It.IsAny<DynamoDBOperationConfig>()))
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
        var function = new PropertySearchFunction(mockDynamoDbContext.Object);
        var response = await function.FunctionHandler(request, context);
        
        // Assert
        Assert.Equal(expectedResponse.Headers, response.Headers);
        Assert.Equal(expectedResponse.StatusCode, response.StatusCode);
        Assert.NotEmpty(response.Body);

        mockDynamoDbContext.Verify(v =>
                v.FromQueryAsync<PropertyRecord>(It.IsAny<QueryOperationConfig>(), It.IsAny<DynamoDBOperationConfig>()),
            Times.Once);

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
}