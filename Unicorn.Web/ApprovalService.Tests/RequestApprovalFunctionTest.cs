// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Net;
using Amazon.DynamoDBv2.DataModel;
using Amazon.DynamoDBv2.DocumentModel;
using Amazon.EventBridge;
using Amazon.EventBridge.Model;
using Amazon.Lambda.APIGatewayEvents;
using Moq;
using Unicorn.Web.Common;
using Xunit;

namespace Unicorn.Web.ApprovalService.Tests;

public class RequestApprovalFunctionTest
{
    public RequestApprovalFunctionTest()
    {
        TestHelpers.SetEnvironmentVariables();
        // Set env variable for Powertools Metrics 
        Environment.SetEnvironmentVariable("POWERTOOLS_METRICS_NAMESPACE","ContractService");
    }
    
    [Fact]
    public async Task RequestApprovalFunction_WhenPropertyFound_SendsApprovalRequest()
    {        
        // Arrange
        var request = TestHelpers.LoadApiGatewayProxyRequest("./events/request_approval_event.json");
        var context = TestHelpers.NewLambdaContext();
        
        var dynamoDbContext = new Mock<IDynamoDBContext>();
        var eventBindingClient = new Mock<IAmazonEventBridge>();

        var searchResult = new List<PropertyRecord>
        {
            new()
            {
                Country = "USA",
                City = "Anytown",
                Street = "Main Street",
                PropertyNumber = "123",
                ListPrice = 2000000.00M,
                Images = new() { "image1.jpg", "image2.jpg", "image3.jpg" }
            }
        };

        dynamoDbContext.Setup(c =>
                c.FromQueryAsync<PropertyRecord>(It.IsAny<QueryOperationConfig>(), It.IsAny<DynamoDBOperationConfig>()))
            .Returns(TestHelpers.NewDynamoDBSearchResult(searchResult));

        // dynamoDbContext.Setup(c => 
        //         c.SaveAsync(It.IsAny<PropertyRecord>(), It.IsAny<CancellationToken>()).ConfigureAwait(false))
        //     .Returns(new ConfiguredTaskAwaitable());

        eventBindingClient.Setup(c =>
                c.PutEventsAsync(It.IsAny<PutEventsRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PutEventsResponse { FailedEntryCount = 0 });

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
        var function = new RequestApprovalFunction(dynamoDbContext.Object, eventBindingClient.Object);
        var response = await function.FunctionHandler(request, context);
        
        // Assert
        Assert.Equal(expectedResponse.Headers, response.Headers);
        Assert.Equal(expectedResponse.StatusCode, response.StatusCode);
        
        dynamoDbContext.Verify(v =>
                v.FromQueryAsync<PropertyRecord>(It.IsAny<QueryOperationConfig>(), It.IsAny<DynamoDBOperationConfig>()),
            Times.Once);

        dynamoDbContext.Verify(v =>
                v.SaveAsync(It.Is<PropertyRecord>(p => p.Status == PropertyStatus.Pending),
                    It.IsAny<CancellationToken>()),
            Times.Once);
        
        eventBindingClient.Verify(v =>
                v.PutEventsAsync(It.Is<PutEventsRequest>(r=> r.Entries.First().DetailType == "PublicationApprovalRequested"),
                    It.IsAny<CancellationToken>()),
            Times.Once);
    }
}