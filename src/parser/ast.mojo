struct Parameter:
    var name: String
    var type_name: String

    def __init__(out self, name: String, type_name: String):
        self.name = name
        self.type_name = type_name


struct IntegerLiteral:
    var value: Int

    def __init__(out self, value: Int):
        self.value = value


struct VariableExpr:
    var name: String

    def __init__(out self, name: String):
        self.name = name


struct BinaryExpr:
    var left: VariableExpr
    var operator: String
    var right: VariableExpr

    def __init__(
        out self,
        left: VariableExpr,
        operator: String,
        right: VariableExpr
    ):
        self.left = left
        self.operator = operator
        self.right = right


struct ReturnStmt:
    var expression: BinaryExpr

    def __init__(out self, expression: BinaryExpr):
        self.expression = expression


struct Function:
    var name: String
    var parameters: List[Parameter]
    var return_type: String
    var body: ReturnStmt

    def __init__(
        out self,
        name: String,
        parameters: List[Parameter],
        return_type: String,
        body: ReturnStmt
    ):
        self.name = name
        self.parameters = parameters
        self.return_type = return_type
        self.body = body