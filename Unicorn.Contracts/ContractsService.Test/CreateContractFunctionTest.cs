// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Collections.Generic;
using System.Net;
using System.Threading.Tasks;
using Amazon.DynamoDBv2.DataModel;
using Amazon.Lambda.APIGatewayEvents;
using Xunit;
using Xunit.Abstractions;
using Moq;
using Unicorn.Contracts.ContractService;

namespace Unicorn.Contracts.Tests;

public class CreateContractFunctionTest
{
    private readonly ITestOutputHelper _testOutputHelper;

    public CreateContractFunctionTest(ITestOutputHelper testOutputHelper)
    {
        _testOutputHelper = testOutputHelper;
    }

    [Fact]
    public async Task CreateValidContractPublishesDraftContractStatusChangedEvent()
    {
        // Arrange
        var request = TestHelpers.LoadApiGatewayProxyRequest("./events/create_valid_event.json");
        
        var mockDynamoDbContext = new Mock<IDynamoDBContext>();

        var mockPublisher = new Mock<IPublisher>();
        
        var context = TestHelpers.NewLambdaContext();

        var expectedResponse = new APIGatewayProxyResponse
        {
            StatusCode = (int)HttpStatusCode.OK,
            Headers = new Dictionary<string, string> { { "Content-Type", "application/json" } }
        };
        
        var function =
            new CreateContractFunction(mockDynamoDbContext.Object, mockPublisher.Object);

        var response = await function.FunctionHandler(request, context);
        
        mockPublisher.Verify(
            client => client.PublishEvent(It.IsAny<Contract>()), Times.Once); //TODO: Verify with contract status = DRAFT
        
        _testOutputHelper.WriteLine("Lambda Response: \n" + response.Body);
        _testOutputHelper.WriteLine("Expected Response: \n" + expectedResponse.Body);

        Assert.Equal(expectedResponse.Headers, response.Headers);
        Assert.Equal(expectedResponse.StatusCode, response.StatusCode);
    }
}