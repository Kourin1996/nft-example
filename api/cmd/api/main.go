package main

import (
	"fmt"
	"io"
	"math/big"
	"net/http"
	"os"
	"strings"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
)

type Token struct {
	Id          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	ExternalUrl string `json:"external_url"`
	Image       string `json:"image"`
}

var idToToken = make(map[string]Token)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	os.MkdirAll("./tmp/images", os.ModePerm)

	e := echo.New()
	e.Use(middleware.Logger())
	e.Use(middleware.Recover())

	e.Use(middleware.Static("tmp"))
	e.GET("/:id", handleGetToken)
	e.POST("/", handlePostToken)

	e.Logger.Fatal(e.Start(":" + port))
}

func canParseInt(value string) bool {
	parsedValue := big.NewInt(0)
	_, ok := parsedValue.SetString(value, 10)
	return ok
}

func getRandomFileName() (string, error) {
	uuidObj, err := uuid.NewRandom()
	if err != nil {
		return "", err
	}
	return uuidObj.String(), nil
}

func getFileExtension(filename string) string {
	arr := strings.Split(filename, ".")
	if len(arr) > 1 {
		return arr[len(arr)-1]
	}
	return ""
}

func handleGetToken(ctx echo.Context) error {
	idParam := ""
	if err := echo.PathParamsBinder(ctx).String("id", &idParam).BindError(); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, "failed to parse id")
	}
	if !canParseInt(idParam) {
		return echo.NewHTTPError(http.StatusBadRequest, "failed to parse id")
	}

	token, ok := idToToken[idParam]
	if !ok {
		return echo.NewHTTPError(http.StatusNotFound, "not found")
	}
	return ctx.JSON(http.StatusOK, token)
}

func handlePostToken(ctx echo.Context) error {
	id := ctx.FormValue("id")
	name := ctx.FormValue("name")
	description := ctx.FormValue("description")
	externalUrl := ctx.FormValue("external_url")
	if !canParseInt(id) {
		return echo.NewHTTPError(http.StatusBadRequest, "failed to parse id")
	}

	file, err := ctx.FormFile("image")
	if err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, "missing file")
	}
	src, err := file.Open()
	if err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, "failed to open file")
	}
	defer src.Close()

	fileName, err := getRandomFileName()
	if err != nil {
		panic(err)
	}
	fileEx := getFileExtension(file.Filename)
	filePath := ""
	if len(fileEx) > 0 {
		filePath = fmt.Sprintf("images/%s.%s", fileName, fileEx)
	} else {
		filePath = fmt.Sprintf("images/%s", fileName)
	}

	dst, err := os.Create("tmp/" + filePath)
	if err != nil {
		return err
	}
	defer dst.Close()
	if _, err = io.Copy(dst, src); err != nil {
		return err
	}

	token := Token{
		Id:          id,
		Name:        name,
		Description: description,
		ExternalUrl: externalUrl,
		Image:       fmt.Sprintf("https://%s/%s", ctx.Request().Host, filePath),
	}
	idToToken[id] = token

	return ctx.JSON(http.StatusCreated, token)
}
